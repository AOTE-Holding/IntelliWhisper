# Intelliwhisper — Development Plan

All design decisions are finalized in concept.md, workflow-ux.md, and technical-spec.md. This plan describes the build order for implementation, starting with zero-dependency components and ending with the components that depend on them.

## Project Structure

```
IntelliWhisper/
├── App/
│   ├── IntelliWhisperApp.swift          # @main entry point, menu bar setup
│   └── AppDelegate.swift                # NSApplicationDelegate, lifecycle
├── Models/
│   └── Types.swift                      # FormatContext, TranscriptionResult, FormattedOutput, PipelineState
├── Protocols/
│   ├── AudioRecording.swift             # AudioRecording protocol
│   ├── Transcribing.swift               # Transcribing protocol
│   ├── ContextDetecting.swift           # ContextDetecting protocol
│   └── Formatting.swift                 # Formatting protocol
├── Services/
│   ├── ClipboardManager.swift           # NSPasteboard wrapper, history, undo
│   ├── ContextDetector.swift            # Layer 1 + Layer 2 detection
│   ├── HotkeyManager.swift             # CGEventTap for Fn key-down/up + Escape
│   ├── OllamaFormatter.swift           # Ollama REST client, streaming, health check
│   ├── WhisperKitRecorder.swift         # AudioProcessor recording
│   └── WhisperKitTranscriber.swift      # WhisperKit transcription + model management
├── Pipeline/
│   └── PipelineOrchestrator.swift       # Wires subsystems, manages state machine
├── UI/
│   ├── MenuBarView.swift                # NSStatusItem, dropdown menu, clipboard history
│   ├── FloatingPanelController.swift    # NSPanel (non-activating), recording/processing/result states
│   ├── FloatingPanelView.swift          # SwiftUI content for the panel
│   └── PreferencesView.swift            # Settings window
└── Setup/
    └── FirstRunView.swift               # Onboarding: permissions, Ollama check, model download
```

## Dependency Graph

```
Data Types & Protocols          (no deps)
    ├── Clipboard Manager       (no deps)
    ├── Context Detector        (macOS APIs only)
    ├── Hotkey Manager          (CGEventTap only)
    ├── Ollama Formatter        (HTTP to localhost)
    └── Audio + Transcription   (WhisperKit)
            │
        Pipeline Orchestrator   (depends on all above)
            │
        UI: Menu Bar + Panel    (depends on pipeline state)
            │
        First-Run + Preferences (depends on UI + all subsystems)
```

---

## Phase 1: Project Scaffold

**Goal:** A macOS app that builds, launches, and shows a menu bar icon.

- Create Xcode project: macOS App, Swift, SwiftUI lifecycle
- Disable App Sandbox in entitlements
- Add `NSMicrophoneUsageDescription` to Info.plist
- Configure `LSUIElement = YES` (no dock icon — menu bar only)
- Add SPM dependencies: WhisperKit, KeyboardShortcuts
- Create a minimal `IntelliWhisperApp.swift` with `MenuBarExtra` that shows an icon
- **Verify:** App builds, launches, icon appears in menu bar, no dock icon

---

## Phase 2: Data Types & Protocols

**Goal:** Define all shared types and subsystem interfaces. No implementations yet.

**Types.swift** — the data types that flow between subsystems:
- `FormatContext` — enum: email, general
- `TranscriptionResult` — struct: text + detected language
- `FormattedOutput` — struct: formatted text + context used
- `PipelineState` — enum: idle, recording, processing, result, error

**Protocol files** — one per subsystem:
- `AudioRecording` — startRecording(), stopRecording() → audio buffer, audioLevel for waveform
- `Transcribing` — transcribe(audio, language) async throws → TranscriptionResult
- `ContextDetecting` — detectContext() → FormatContext
- `Formatting` — format(transcription, context, language) → AsyncThrowingStream, healthCheck() async → Bool

**Verify:** Project builds with all types and protocols defined, no implementations yet.

---

## Phase 3: Independent Components

These three have no cross-dependencies and can be built in any order.

### 3a. Clipboard Manager

**File:** `ClipboardManager.swift`
- `copy(text:)` — saves current clipboard content to history, then writes new text via `NSPasteboard.general`
- `undo()` — restores the most recently overwritten clipboard content
- `history` — in-memory array of the last 5 overwritten items
- **Verify:** Copy text, check history contains previous item, test undo restores it

### 3b. Context Detector

**File:** `ContextDetector.swift`, conforms to `ContextDetecting`
- Layer 1: Match `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` against a dictionary of known apps (see technical-spec.md §3 for the full mapping)
- Layer 2: If a browser is detected, call `CGWindowListCopyWindowInfo`, find the window by PID, match `kCGWindowName` against title patterns (Gmail, Outlook, Slack, etc.)
- Fallback: return `.general` if no match
- **Verify:** Switch to Mail, Slack, Chrome-on-Gmail, call detectContext(), confirm correct format returned

### 3c. Hotkey Manager

**File:** `HotkeyManager.swift`
- Install `CGEventTap` at session level for `flagsChanged` events
- Monitor `.maskSecondaryFn` in `CGEventFlags` to detect Fn key-down and key-up
- Detect Escape key press while Fn is held (discard gesture)
- Expose callbacks: `onRecordStart`, `onRecordStop`, `onDiscard`
- **Verify:** Hold Fn → "start" logged, release → "stop" logged, Fn + Escape → "discard" logged. Requires Input Monitoring permission grant.

---

## Phase 4: External Integration Components

### 4a. Ollama Formatter

**File:** `OllamaFormatter.swift`, conforms to `Formatting`
- `healthCheck()` — `GET http://localhost:11434/api/tags`, verify the configured model (default `qwen3.5:0.8b`) is in the response
- `format(transcription:context:language:)` — `POST /api/chat` with `stream: true`. System prompt as defined in technical-spec.md §4. Returns `AsyncThrowingStream<String, Error>` for token-by-token delivery.
- 15-second timeout. On error or timeout, throw so the pipeline can fall back to raw transcription.
- Use `URLSession` with async bytes — no third-party HTTP dependency needed.
- **Verify:** With Ollama running and qwen3.5:0.8b pulled, call format() with a test German transcription, confirm streamed tokens arrive and form a coherent cleaned-up output

### 4b. Audio Capture

**File:** `WhisperKitRecorder.swift`, conforms to `AudioRecording`
- Wraps WhisperKit's `AudioProcessor`
- `startRecording()` — begin microphone capture (16kHz mono Float32)
- `stopRecording() -> [Float]` — stop capture, return audio buffer
- Expose `audioLevel: Float` (updated continuously) for waveform visualization
- If recording duration < 0.5 seconds, return empty buffer (accidental press)
- **Verify:** Start recording, speak for 3 seconds, stop, confirm non-empty Float array returned

### 4c. Transcription

**File:** `WhisperKitTranscriber.swift`, conforms to `Transcribing`
- Initialize `WhisperKit` with model folder at `~/Library/Application Support/IntelliWhisper/Models/`
- On first use: download the configured model (default: `small`) from Hugging Face, report progress via callback
- `transcribe(audio:language:)` — configure `DecodingOptions` (language default `"de"`, task `.transcribe`), return `TranscriptionResult` with `.text` and `.language`
- Return empty result if transcription is whitespace-only
- **Verify:** Feed a recorded audio buffer, confirm German text transcription returned with correct language code

---

## Phase 5: Pipeline Orchestrator

**File:** `PipelineOrchestrator.swift`
- Owns instances of all four protocol-typed subsystems + ClipboardManager
- Publishes `@Published state: PipelineState` (observed by UI)
- Wired to HotkeyManager callbacks:
  - `onRecordStart` → run context detection, start audio recording, set state `.recording`
  - `onRecordStop` → stop recording, set state `.processing`, transcribe audio, format via Ollama (streaming), copy final result to clipboard, set state `.result(output)`
  - `onDiscard` → stop recording, discard buffer, set state `.idle`
- Fallback paths:
  - Ollama unavailable or timeout → copy raw transcription, set state `.result` with raw text
  - Empty transcription → set state `.error("No speech detected.")`
- **Verify:** Full pipeline — hold Fn over Gmail, speak a sentence, release, confirm clipboard contains a formatted email with greeting/closing. Hold Fn over Slack, speak, release, confirm clipboard contains lightly cleaned-up text (no restructuring). Repeat with Ollama stopped — confirm raw transcription on clipboard.

---

## Phase 6: UI

### 6a. Menu Bar

**File:** `MenuBarView.swift`
- `NSStatusItem` with SF Symbol icon
- Icon reflects state: default (idle), red dot (recording), yellow dot (Ollama unavailable)
- Dropdown menu: clipboard history items (clickable to re-copy), separator, Preferences, Quit

### 6b. Floating Panel

**Files:** `FloatingPanelController.swift` + `FloatingPanelView.swift`
- `NSPanel` configured as non-activating (`.nonactivatingPanel | .utilityWindow`), floating level
- Positioned below the menu bar icon
- Observes `PipelineOrchestrator.state` and shows:
  - `.recording` → waveform animation driven by `audioLevel` + duration timer
  - `.processing` → spinner / progress indicator
  - `.result` → formatted text, auto-hides after configured preview duration (~2s)
  - `.error` → error message, auto-hides after 2s
- Escape during `.result` → call `ClipboardManager.undo()`, hide panel immediately

### 6c. Preferences

**File:** `PreferencesView.swift`
- SwiftUI Settings form:
  - Hotkey picker (default: Fn/Globe)
  - Language selector: German, English, Auto-detect (default: German)
  - Preview duration slider (default: 2 seconds)
  - Ollama model picker (default: qwen3.5:0.8b, populated from installed Ollama models)
- Persist all settings via `@AppStorage` / `UserDefaults`

**Verify:** Full UX flow end-to-end. Hold Fn → panel with waveform → release → processing spinner → result preview → auto-hide. Menu bar icon changes state. Preferences open and persist.

---

## Phase 7: First-Run & Polish

**File:** `FirstRunView.swift`
- Step-by-step onboarding shown on first launch:
  1. Microphone permission — trigger system prompt, explain why
  2. Screen Recording permission — explain it only reads window titles, not screen content
  3. Input Monitoring permission — explain it captures the hotkey only
  4. Fn key check — if system is set to emoji picker, show instructions to change it
  5. Ollama check — check reachability, auto-pull default model (`qwen3.5:0.8b`) with progress if missing, show install instructions (`brew install ollama`, `ollama serve`) if Ollama not running
  6. WhisperKit model download — progress bar, download on button press
- Store `setupCompleted` flag in UserDefaults. Skip on subsequent launches.

**Remaining doc fixes:**
- workflow-ux.md line 113: `gemma3:4b` → `qwen3.5:0.8b`
- workflow-ux.md line 110: clarify Screen Recording doesn't record the screen
- workflow-ux.md: add note that first launch requires internet for model download
- workflow-ux.md preferences: add Launch at Login option

**Verify end-to-end:** Fresh launch → first-run → permissions → model download → hold Fn in Gmail → speak → release → formatted email on clipboard → Cmd+V into Gmail. Test both contexts (email, general). Test Ollama-down fallback. Test discard (Fn + Escape). Test clipboard history and undo.
