# Concurrency & Parallelism Analysis

## Current Pipeline

```
Hotkey release
  ├─ transcriber.transcribe(audio)     ~1–4s  (WhisperKit → Neural Engine)
  ├─ formatter.format(text)            ~0.5–3s (Ollama → GPU via Metal)
  └─ clipboard.copy(text)              ~instant
                                       Total: ~2–7s after key release
```

Both stages run sequentially — formatting needs the transcription text.

---

## Hardware Context

On Apple Silicon, WhisperKit runs on the **Neural Engine (ANE)** while Ollama runs on the **GPU (Metal)**. These are separate hardware units sharing unified memory. They can run concurrently without competing for compute.

---

## Transcription

### What won't help

- **Parallel chunk processing**: The ANE serializes inference requests. Running multiple TranscribeTasks concurrently competes for the same ANE — benchmarks show parallel GPU jobs *double* execution time due to contention.
- **`concurrentWorkerCount`**: Exists in WhisperKit but designed for multiple audio files, not splitting one recording.

### Background: chunking and VAD chunking

Whisper processes audio in fixed **30-second windows**. For recordings shorter than 30s, the entire audio fits in one window and is transcribed in a single pass. For longer recordings (common — users often dictate for 2–3 minutes), the audio must be split into multiple windows.

**Naive chunking** simply cuts the audio every 30 seconds, which can split mid-word or mid-sentence, degrading transcription quality at chunk boundaries.

**VAD (Voice Activity Detection) chunking** is smarter: it analyzes energy levels to find natural silence points (pauses between sentences or phrases) and splits there. This produces cleaner chunk boundaries and better transcription accuracy. WhisperKit implements this via `VADAudioChunker` using `EnergyVAD`. It is enabled by setting `chunkingStrategy: .vad` in `DecodingOptions`.

Without VAD chunking enabled, recordings >30s fall back to the default single-window behavior, which truncates audio beyond the window size. **This is a correctness issue, not just a performance one.**

### What will help

| Approach | Description | Latency gain | Complexity |
|----------|-------------|-------------|------------|
| **Streaming transcription** | Use WhisperKit's `AudioStreamTranscriber` to transcribe incrementally *while the user speaks*. On key release, most audio is already transcribed. | High — near-zero post-release latency | High (rewrite recorder, transcriber, orchestrator) |
| **VAD chunking** | Add `chunkingStrategy: .vad` to `DecodingOptions`. Required for recordings >30s (2–3 minute dictations are common). Without it, audio beyond 30s is truncated. | Critical for correctness | 1 line |

#### Streaming transcription details

WhisperKit's `AudioStreamTranscriber` processes each ~1s audio buffer as it arrives during recording. It maintains confirmed vs unconfirmed segments, using a segment confirmation heuristic.

- **Quality**: Batch transcription is ~0.5% WER more accurate (WhisperKit paper). Acceptable for speech cleanup.
- **Confirmed text latency**: ~1.7s from speech to confirmed segment.
- **Existing code**: Built into WhisperKit at `.build/checkouts/WhisperKit/Core/Audio/AudioStreamTranscriber.swift`.

---

## Formatting (Ollama)

### What won't help

- **Splitting text into parallel requests**: Ollama supports `OLLAMA_NUM_PARALLEL` (batched GPU forward passes), but splitting a 3-sentence input into 3 requests adds 3x prompt processing overhead and risks inconsistent formatting. Throughput is shared, not multiplied.
- **Speculative partial formatting**: Starting Ollama with incomplete text produces garbage, especially for emails (needs full context for greeting/closing). Speculative decoding is not yet supported in Ollama (open issue #5800).

### What will help

| Approach | Description | Latency gain | Complexity |
|----------|-------------|-------------|------------|
| **Warmup on record start** | Fire `formatter.warmup()` when the hotkey is pressed. Runs on GPU while recording uses ANE — zero contention. Change `keep_alive` to `"-1"` (never evict model from VRAM). | High — eliminates 2–5s cold-start after idle | Very low (1 line + config change) |
| **Reduce context window** | Set `num_ctx: 1024` and `num_predict: 512`. Our prompts are short; smaller KV cache = faster prompt processing. | Low–medium (~10–30%) | Very low (2 fields in request options) |
| **Skip for short general text** | If context is `.general` and input ≤10 words, skip Ollama entirely. Light cleanup adds negligible value for "Sounds good, thanks." | Medium (saves 0.5–2s) | Very low (threshold check) |

---

## Pipeline-Level Parallelism

### Overlap transcription and formatting

With streaming transcription, confirmed segments become available during recording. On key release:

1. Start Ollama formatting with confirmed text immediately
2. Finish transcribing the final audio buffer on ANE concurrently
3. If the final buffer adds new text, append or re-format

This works because **ANE and GPU are separate hardware**. Requires streaming transcription as a prerequisite.

- **Latency gain**: Very high — formatting starts 1–3s earlier
- **Complexity**: Very high — careful coordination of partial results
- **Risk**: Final buffer may change meaning; need re-format fallback

### Simpler variant: warmup during recording

Even without streaming transcription, warming up Ollama during recording overlaps GPU warmup with ANE recording — different hardware, genuine parallelism.

---

## Summary

| # | Approach | Stage | Gain | Effort | Recommend |
|---|---------|-------|------|--------|-----------|
| 1 | Warmup Ollama on record start + `keep_alive: -1` | Formatting | High | Very low | **Yes — do first** |
| 2 | Reduce `num_ctx` + `num_predict` | Formatting | Low–medium | Very low | **Yes — do first** |
| 3 | Skip Ollama for ≤10-word general text | Formatting | Medium | Very low | **Yes — do first** |
| 4 | VAD chunking for >30s audio | Transcription | Critical (correctness) | Very low | **Yes — required** |
| 5 | Streaming transcription during recording | Transcription | High | High | Yes (major effort) |
| 6 | Overlap streaming transcription + formatting | Pipeline | Very high | Very high | Future (needs #5) |

### Estimated impact of quick wins (#1–4)

- **Best case** (cold Ollama + short general text): ~4–7s → ~0s (skip Ollama entirely)
- **Typical short dictation** (warm Ollama, <30s): ~3–5s → ~2–4s (context reduction)
- **Typical long dictation** (warm Ollama, 2–3 min): ~8–15s → ~7–12s (VAD chunking enables correct transcription; context reduction helps formatting)
- **Worst case** (long email dictation): ~10–15s → ~8–12s (context reduction only)

### Estimated impact with streaming transcription (#5–6)

- **Typical case**: ~3–5s → ~0.5–1.5s (transcription overlaps with speaking, formatting starts immediately)
