# Intelliwhisper — Workflow & User Experience

## Overview

Intelliwhisper is a macOS menu bar utility for speech-to-text. The user holds a hotkey, speaks, releases the key, and receives a formatted text snippet on their clipboard — ready to paste. The app runs entirely on-device with no internet connection required.

---

## What the User Sees

### Menu Bar Icon

A small icon sits in the macOS menu bar at all times while the app is running. It communicates four states:

| State | Icon appearance |
|-------|----------------|
| Loading | Download arrow icon (while WhisperKit model loads at startup) |
| Idle | Default monochrome waveform icon |
| Recording | Filled record circle icon |
| Ollama unavailable | Warning triangle icon |

Clicking the icon opens a dropdown menu with:
- **Clipboard history** — the last 5 formatted results, each clickable to re-copy
- **Preferences** — opens a settings window
- **Quit** — exits the app

### Floating Panel

A small floating window that appears during the recording and processing workflow. It does **not** steal keyboard focus — the user's cursor remains in whichever app they were typing in.

The panel appears anchored near the menu bar icon (or at a user-configured position) and shows one of three states:

**1. Recording State**
- A pulsing red circle indicator showing that audio is being captured
- A duration timer counting up (e.g., "0:03")
- Tags showing the detected context (Email/General) and whether formatting is enabled
- Visible as long as the user holds the hotkey

**2. Processing State**
- Replaces the recording indicator after the user releases the hotkey
- Shows a progress indication while WhisperKit transcribes and Ollama formats
- Transitions to the result state once formatting is complete

**3. Result State**
- Displays the formatted text (the final output that was copied to the clipboard)
- Remains visible for approximately 2 seconds, then auto-hides
- If the user presses Escape during this window, the copy is undone (previous clipboard content restored)

---

## Core Workflow: Hold → Speak → Release → Paste

### Step-by-step

1. **User is working in any app** (e.g., Gmail in Chrome, Slack, Apple Mail, Notes).

2. **User holds the configured hotkey** (default: Fn/Globe). At the moment of key-down:
   - The app detects the currently active application and window title. This determines the output format (email or general).
   - The floating panel appears in the "Recording" state.
   - The menu bar icon changes to indicate active recording.
   - Audio capture begins via WhisperKit.

3. **User speaks** while continuing to hold the hotkey. They can speak for as long as needed. The floating panel shows a pulsing indicator and duration counter.

4. **User releases the hotkey.** At key-up:
   - Audio capture stops.
   - The floating panel transitions to "Processing" state.
   - WhisperKit transcribes the audio locally.
   - The transcription and detected context are sent to the local Ollama instance for cleanup. For general context, light cleanup is applied (grammar, punctuation, filler word removal). For email context, full formatting is applied (greeting, closing, professional tone).
   - Once cleanup completes, the result is either copied to the clipboard or auto-pasted into the active app (depending on the configured output mode).
   - The floating panel briefly shows the result (~2 seconds), then auto-hides.
   - The menu bar icon returns to idle state.

5. **User presses Cmd+V** in their target app (if using clipboard mode). In paste mode, the text is inserted automatically.

### Discard Gesture

If the user realizes mid-recording that they want to start over or cancel:

- **While still holding the hotkey, press Escape.** This discards the recording entirely. No transcription occurs, nothing is copied to the clipboard, and the floating panel hides immediately. The user can then hold the hotkey again to start a fresh recording.

### Clipboard Safety

Every time a new result is copied, the previous clipboard content is preserved in a short history (last 5 items) accessible from the menu bar dropdown. If the user accidentally overwrites something important, they can recover it from there.

Additionally, during the ~2-second result preview, pressing Escape restores the previous clipboard content.

---

## Context-Aware Cleanup

The app inspects the active application at the moment the user starts recording to determine the context:

| Detected context | Cleanup behavior |
|-----------------|------------------|
| Email app or webmail (Mail, Gmail, Outlook, Yahoo Mail) | **Full formatting:** adds greeting and closing, professional tone. German defaults to "Sie" unless the speaker uses "du". |
| Anything else | **Light cleanup only:** fixes grammar, punctuation, removes filler words. No restructuring. |

The user does not need to manually select a format. The detection is automatic and silent. For non-email contexts, the output stays as close to the speaker's original words as possible.

---

## First-Run Experience

On first launch, the app guides the user through setup:

1. **Microphone permission** — system prompt to allow microphone access.
2. **Screen Recording permission** — system prompt to allow reading window titles (needed for context detection). The app explains why this is needed.
3. **Input Monitoring permission** — system prompt to allow capturing the hotkey globally.
4. **Fn key configuration** — if the default Fn hotkey is active and macOS is configured to use Fn for the emoji picker, the app shows instructions to change System Settings → Keyboard → "Press fn key to" → "Do Nothing". A note informs the user that the hotkey can be changed later in Preferences.
5. **Ollama check** — the app checks if Ollama is running. If not, it shows install instructions (`brew install ollama`, `ollama serve`). This step can be skipped.
6. **WhisperKit model download** — the Whisper model (default: small, ~460 MB) is downloaded on first use and cached locally. A progress indicator shows the download status.

After setup, the app is ready. All subsequent launches skip setup entirely.

---

## Preferences

Accessible from the menu bar dropdown. Settings include:

- **Language** — preferred transcription language (default: German). Options: German, English, Auto-detect.
- **Whisper model** — which WhisperKit model to use for transcription (selectable from available sizes: tiny, base, small, large-v3-turbo). Shows model size and a "Recommended" badge on the default (small).
- **Hotkey** — push-to-talk key. Options: Fn (Globe), Right Option (⌥), § (left of 1). Default: Fn. Shows a hint about the Fn/emoji picker system setting when Fn is selected.
- **Output mode** — what happens after transcription: "Copy to clipboard" (default) or "Paste directly" (simulates Cmd+V; requires Accessibility permission).
- **Formatting toggles** — independently enable/disable formatting for general and email contexts. When all formatting is disabled, raw transcription is used.
- **Ollama model** — which model to use for text cleanup (default: hardware-dependent, `qwen3.5:2b` on <16 GB RAM or `qwen3.5:4b` on 16 GB+). Populated from installed Ollama models; falls back to a text field if Ollama is unreachable. Shows a connection status indicator (green/yellow).

---

## Edge Cases & Fallback Behavior

| Situation | What happens |
|-----------|--------------|
| Ollama is not running | Recording and transcription work normally. Raw (unformatted) transcription is copied to clipboard. Yellow warning on menu bar icon. |
| Very short recording (<0.5s) | Treated as accidental press. Nothing happens. Panel does not appear. |
| No speech detected in recording | Panel shows "No speech detected." Nothing is copied. |
| Hotkey not available / intercepted by macOS | User configures an alternative hotkey in Preferences. |
| Screen Recording permission denied | Context detection falls back to bundle identifier matching only. Browser tab detection is unavailable, but native apps still detected. |
| Accessibility permission denied (paste mode) | Auto-paste is skipped; text is still copied to the clipboard. The user can paste manually with Cmd+V. |
