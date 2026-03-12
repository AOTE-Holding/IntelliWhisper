# Intelliwhisper — Technical Specification

## Architecture Overview

Intelliwhisper is a non-sandboxed macOS application written in Swift, distributed as a notarized .app bundle via direct download (not App Store). It consists of four core subsystems:

1. **Hotkey & Audio Capture** — captures the Fn key globally and records microphone audio
2. **Transcription** — converts audio to text using WhisperKit (on-device)
3. **Context Detection** — identifies the active application and infers the target format
4. **Formatting** — sends transcription + context to a local Ollama instance for text formatting

These subsystems execute in a pipeline triggered by the hotkey press/release cycle.

### Design Principles

The architecture must prioritize **extensibility and maintainability** from the start:

- **Protocol-driven subsystems.** Each of the four subsystems (audio capture, transcription, context detection, formatting) must be defined by a Swift protocol. Concrete implementations (WhisperKit, Ollama, CGWindowList-based detection) conform to these protocols. This allows swapping or adding implementations — e.g., replacing WhisperKit with another STT engine, or Ollama with a different LLM backend — without changing the pipeline or the rest of the app.
- **Decoupled pipeline.** Subsystems communicate through well-defined data types (`AudioBuffer`, `TranscriptionResult`, `FormatContext`, `FormattedOutput`), not by calling each other directly. The pipeline orchestrator passes data between stages. Adding a new stage (e.g., post-processing, translation) means inserting it into the pipeline without modifying existing subsystems.
- **Isolated side effects.** Permissions, network calls, and clipboard access are confined to their respective subsystems. UI code never calls Ollama directly; the formatting subsystem never touches the clipboard. This keeps each layer testable and replaceable independently.
- **Additive feature growth.** New format types (e.g., "Jira ticket", "commit message") should require only a new `FormatContext` case and a prompt addition — no structural changes. New email detection rules (e.g., a new webmail provider) should require only adding a string to the lookup table, not code changes.

---

## 1. Hotkey & Audio Capture

### Global Hotkey

The app must capture key-down and key-up events for the Fn (Globe) key system-wide, regardless of which app is focused. This requires a `CGEventTap` installed at the session level.

- **API:** `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)` with `CGEventTapLocation.cgSessionEventTap`.
- **Events of interest:** `CGEventMask` for `keyDown` and `keyUp`, plus `flagsChanged` (modifier keys including Fn emit `flagsChanged` events, not regular key events).
- **Permission:** Input Monitoring (macOS will prompt the user via System Settings → Privacy & Security → Input Monitoring).
- **Fn key specifics:** The Fn/Globe key on Apple keyboards sets a flag in `CGEventFlags` (`.maskSecondaryFn`). The app monitors `flagsChanged` events and checks for the presence/absence of this flag to determine key-down and key-up.
- **Fallback:** If a user configures a different hotkey (e.g., Right Option, or a modifier combo), the same `CGEventTap` approach applies. The [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package can simplify configurable hotkey registration, though it uses `RegisterEventHotKey` which does not provide key-up events — a custom `CGEventTap` implementation may be necessary for push-to-talk.

### Audio Recording

Audio capture uses WhisperKit's `AudioProcessor` component.

- **API:** `AudioProcessor` from WhisperKit provides microphone access and buffered audio capture, outputting audio in the format Whisper expects (16kHz mono Float32).
- **Permission:** Microphone access (`NSMicrophoneUsageDescription` in Info.plist).
- **Start:** On Fn key-down, begin audio capture via `AudioProcessor.startRecording()`.
- **Stop:** On Fn key-up, stop capture via `AudioProcessor.stopRecording()`. The buffered audio data is passed to the transcription subsystem.
- **Discard:** On Escape pressed while Fn is held, stop capture and discard the audio buffer. No transcription is triggered.
- **Minimum duration:** If the recording is shorter than 0.5 seconds, discard it as an accidental press.

---

## 2. Transcription (WhisperKit)

### Model

- **Model:** Whisper `small` by default (configurable in preferences; options: tiny, base, small, large-v3-turbo).
- **Runtime:** WhisperKit runs the model via Apple's Core ML framework on Apple Silicon.
- **Model storage:** Downloaded from Hugging Face on first launch. Cached in `~/Library/Application Support/IntelliWhisper/Models/`. Not bundled with the app to keep the initial download small.

### Transcription Call

```swift
let whisperKit = try await WhisperKit(modelFolder: modelPath)
let result = try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
```

- **`DecodingOptions`:**
  - `language`: User-configured preferred language (default: `"de"` for German). When set to `nil`, auto-detection is used.
  - `task`: `.transcribe` (not `.translate`)
  - `detectLanguage`: `true` when no preferred language is set.
- **Output:** `TranscriptionResult` containing `.text` (the raw transcription string) and `.language` (detected language code).
- **Performance:** On Apple Silicon MacBooks, the small model transcribes ~30 seconds of audio in a few seconds. Larger models (large-v3-turbo) offer better accuracy but require more memory and longer load times.

### Empty Result Handling

If `result.text` is empty or contains only whitespace/filler, the pipeline stops. The floating panel shows "No speech detected." and no clipboard operation occurs.

---

## 3. Context Detection

Context detection runs **once at Fn key-down** (recording start) and produces a `FormatContext` value used later by the formatting subsystem.

### Layer 1: Bundle Identifier

```swift
let app = NSWorkspace.shared.frontmostApplication
let bundleId = app?.bundleIdentifier
```

No permission required. Provides the bundle identifier of the foreground app. Matched against a set of known email app identifiers:

| Bundle Identifier | Format |
|-------------------|--------|
| `com.apple.mail` | email |
| `com.microsoft.Outlook` | email |

If the bundle identifier matches a known browser (`com.google.Chrome`, `com.apple.Safari`, `com.microsoft.edgemac`, `company.thebrowser.Browser`, `com.brave.Browser`, `org.mozilla.firefox`), proceed to Layer 2.

### Layer 2: Window Title

```swift
let windowList = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]]
```

- **Permission:** Screen Recording (prompted by macOS on first call).
- **Approach:** Find the window owned by the frontmost app's PID (`kCGWindowOwnerPID`) that is on-screen. Read `kCGWindowName` (the window title).
- **Matching:** Apply substring matching against the window title:

| Window title contains | Format |
|----------------------|--------|
| "Gmail" | email |
| "Outlook" | email |
| "Yahoo Mail" | email |

- **Fallback:** If Screen Recording permission is denied, Layer 2 is skipped. The app relies on Layer 1 alone. Browser-based webmail will produce `general` context (light cleanup only).

### Context Result

The detection produces a `FormatContext` enum:

```swift
enum FormatContext {
    case email    // full formatting (greeting, closing, professional tone)
    case general  // light cleanup only (grammar, filler words, repetitions)
}
```

---

## 4. Formatting (Ollama)

### Connection

The app communicates with Ollama via its local HTTP API at `http://localhost:11434`.

- **Library:** Use [OllamaKit](https://github.com/kevinhermawan/OllamaKit) or direct `URLSession` calls against the Ollama REST API.
- **Endpoint:** `POST /api/chat` with `stream: true`.
- **Model:** `qwen3.5:0.8b` (configurable in preferences). Thinking mode disabled (`think: false`).

### Health Check

On app launch (and periodically), the app calls `GET /api/tags` to verify:
1. Ollama is reachable at localhost:11434.
2. The configured model (`qwen3.5:0.8b`) is present in the model list.

If either check fails, the menu bar icon shows a yellow warning indicator. Recording still works — the fallback is to copy the raw transcription to the clipboard without formatting.

### Prompt Construction

The system prompt is static and defines minimal-intervention cleanup behavior:

```
Fix grammar, punctuation, and remove filler words (um, uh, ähm).
Remove accidental repetitions. Do not restructure or rephrase.
Keep the same language. Output only the corrected text.

If context is EMAIL: add greeting and closing, use professional tone.
German emails default to "Sie" unless "du" is explicit.
```

The user message provides the context and transcription:

```
Context: {EMAIL|GENERAL}
Language: {language_code}

{raw_transcription_text}
```

### Streaming Response

The Ollama response is streamed. Each chunk is appended to the floating panel's result view in real time, providing visual feedback that formatting is in progress. Once the stream completes:
1. The final formatted text is copied to the clipboard.
2. The floating panel shows the complete result for the configured preview duration (~2 seconds), then auto-hides.

### Timeout & Error Handling

- **Timeout:** If Ollama does not respond within 15 seconds, cancel the request and fall back to the raw transcription.
- **Malformed response:** If the response is empty or clearly not a formatted version of the input, fall back to raw transcription.
- **Model cold start:** The first request after Ollama loads the model may take longer (model loads into memory). Subsequent requests are fast (~200ms to first token).

---

## 5. Clipboard Management

### Write

After formatting (or raw fallback), the result is written to the system clipboard via `NSPasteboard.general`:

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(formattedText, forType: .string)
```

Before clearing, the current clipboard content is saved to the clipboard history.

### History

The app maintains an in-memory array of the last 5 clipboard items that were overwritten by Intelliwhisper. These are displayed in the menu bar dropdown and can be re-copied with a click. The history is not persisted across app restarts.

### Undo

During the ~2-second result preview window, pressing Escape restores the previous clipboard content (the item that was overwritten).

---

## 6. Permissions Summary

| Permission | macOS API | Info.plist key | Purpose |
|-----------|-----------|----------------|---------|
| Microphone | `AVCaptureDevice` | `NSMicrophoneUsageDescription` | Audio recording |
| Screen Recording | `CGWindowListCopyWindowInfo` | (System-managed, no plist key) | Reading window titles for Layer 2 context detection |
| Input Monitoring | `CGEvent.tapCreate` | (System-managed, no plist key) | Capturing global Fn key-down/key-up events |

All permissions are prompted by macOS on first use. The app does not require Accessibility permission (no simulated keystrokes) or Apple Events permission (no AppleScript in v1).

The app must **not** be sandboxed. The App Sandbox prevents `CGWindowListCopyWindowInfo` from returning window titles and blocks `CGEventTap` creation.

---

## 7. Distribution

- **Format:** Standard `.app` bundle in a `.dmg` disk image.
- **Signing:** Signed with an Apple Developer ID certificate.
- **Notarization:** Submitted to Apple for notarization to avoid Gatekeeper warnings.
- **Auto-update:** Consider [Sparkle](https://sparkle-project.org/) for in-app update checking (optional, not required for v1).
- **Model delivery:** WhisperKit model downloaded on first launch from Hugging Face. Ollama and its model are installed separately by the user.

---

## 8. Dependencies

| Dependency | Purpose | Integration |
|-----------|---------|-------------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Speech-to-text transcription | Swift Package Manager |
| [OllamaKit](https://github.com/kevinhermawan/OllamaKit) or direct URLSession | LLM formatting via Ollama API | Swift Package Manager or built-in |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Configurable hotkey UI (preferences) | Swift Package Manager |
| Ollama (external) | Local LLM runtime | User-installed, communicates via HTTP |
