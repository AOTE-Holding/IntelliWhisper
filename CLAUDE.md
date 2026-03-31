# IntelliWhisper

Privacy-first macOS menu bar app for local speech-to-text. Hold hotkey → speak → release → formatted text on clipboard. All processing local via WhisperKit (transcription) + Ollama (formatting).

## Core Principles

- NEVER add "Generated with Claude Code" or "Co-Authored by Claude Code" to commits, specs, or code
- Use web search when you need information about tech stacks and interfaces. Ask when you need clarification
- Use `xcodebuild` for macOS app builds
- Use `scp` to copy files to/from remote servers
- Always ask the user about their long-term vision
- NEVER estimate time to fix or time to plan
- Always use Docker and docker-compose for app services (log cycling, automatic restart, isolated envs)
- NEVER use /tmp for project data — always use project folder for sensitive data
- When creating GitHub repos, ALWAYS make them private

## Tech Stack

- **Swift 6.0+** with SwiftUI + AppKit, macOS 14+ (Sonoma)
- **Swift Package Manager** for dependencies (Package.swift + Package.resolved)
- **WhisperKit 0.12.0** — local Whisper model transcription via CoreML
- **Ollama** — local LLM formatting at `http://localhost:11434`
- **SwiftyBeaver 2.1.0** — structured logging to `~/Library/Logs/IntelliWhisper/intelliwhisper.log`
- App is **non-sandboxed** (required for CGEventTap global hotkey + window title reading)
- Distributed as `.pkg` installer, not App Store

## Project Structure

```
Sources/IntelliWhisper/
  App/                  # @main entry point + AppDelegate
  Models/               # Types.swift (shared types), HotkeyChoice.swift
  Protocols/            # Interfaces: AudioRecording, Transcribing, ContextDetecting, Formatting
  Services/             # Implementations: WhisperKitRecorder, WhisperKitTranscriber,
                        #   OllamaFormatter, ContextDetector, ClipboardManager, HotkeyManager,
                        #   SettingsService (centralized UserDefaults), Log
  Pipeline/             # PipelineOrchestrator (central state machine), AppInitializer
  UI/                   # MenuBarView, MenuBarController, FloatingPanel*, PreferencesView
  Setup/                # FirstRunCoordinator + FirstRunView (onboarding wizard)
Resources/              # Info.plist, entitlements, app icon
scripts/build.sh        # Build script: ./scripts/build.sh [--release|--pkg|--zip|--all]
testing/                # test_data.json + run_tests.sh (manual Ollama model evaluation)
```

## Architecture

Protocol-driven design with central orchestrator state machine:

```
SettingsService (centralized UserDefaults, @Published, injected into all subsystems)
Hotkey (CGEventTap) → HotkeyManager → PipelineOrchestrator
  ├→ ContextDetector   (detect active app: email vs general)
  ├→ WhisperKitRecorder (capture audio)
  ├→ WhisperKitTranscriber (speech-to-text)
  ├→ OllamaFormatter   (LLM text cleanup, streaming)
  └→ ClipboardManager  (copy/paste + history)
UI: MenuBarController, FloatingPanelController, PreferencesView observe @Published state
```

**PipelineState:** `idle → recording → processing → result | error`

**Graceful degradation:** Works without Ollama (raw transcription), without Screen Recording (bundle-only context detection), without Accessibility (no auto-paste).

## Key Patterns

- **@MainActor isolation** for all state mutations — Swift concurrency throughout, no DispatchQueue
- **Protocol-driven subsystems** — each service implements a protocol, swappable
- **Combine @Published** — UI observes orchestrator state changes
- **Non-blocking UI** — FloatingPanel is non-activating NSPanel; long ops are async
- **Sendable types** — thread safety via Swift concurrency; `nonisolated(unsafe)` only for CGEventTap callbacks
- **Streaming Ollama** — HTTP streaming via `URLSession.bytes`, newline-delimited JSON, tokens yielded via AsyncThrowingStream

## macOS Permissions Required

- **Microphone** — core recording (AVCaptureDevice)
- **Input Monitoring** — global hotkey (CGEventTap)
- **Screen Recording** — window title reading for context detection (optional)
- **Accessibility** — simulated Cmd+V paste (optional)

## User Settings (UserDefaults via SettingsService)

All keys, defaults, and persistence logic are centralized in `SettingsService`. Non-MainActor services (OllamaFormatter, HotkeyManager) read via `SettingsService.Keys` statics against UserDefaults directly.

`preferredLanguage`, `whisperModel`, `ollamaModel`, `hotkeyChoice`, `outputMode`, `formatGeneral`, `formatEmail`, `generalSystemPrompt`, `emailSystemPrompt`, `setupCompleted`

## Build & Run

```bash
swift build                              # Debug build
./scripts/build.sh --release             # Release build
./scripts/build.sh --release --pkg       # .pkg installer
./scripts/build.sh --release --all       # All artifacts (pkg + zip + direct)
```

**Two-app bundle architecture (TCC workaround):** macOS ties permissions (Microphone, Input Monitoring, Screen Recording) to app bundle identity. `swift build` produces a bare binary, so the build script wraps it into **"IntelliWhisper Core.app"** — the real app bundle that holds the Info.plist, entitlements, and bundle ID (`de.intellilab.IntelliWhisper`) that TCC recognizes. A separate **"IntelliWhisper.app"** launcher (bundle ID `de.intellilab.IntelliWhisper.Launcher`) is a minimal shell-script app that launches the Core binary. The launcher is what goes in the Dock and what the user double-clicks; the Core app is what actually runs and owns the permissions. Both live side-by-side in `/Applications/IntelliWhisper/`. Without this split, permissions would attach to "Terminal" or "applet" instead of the app.

Models cached at `~/Library/Application Support/IntelliWhisper/Models/` (downloaded from HuggingFace on first launch).

## Workflow

1. Gather info: read, research, ask user
2. Define goal: ask user about goal, plan next steps
3. Ask user whether they are happy with plan
4. Test using automated tests or manual testing / ask user for results
5. Commit/push to GitHub
6. Restart cycle

## Database Migrations

- ALL migrations MUST be non-destructive. Never use DROP COLUMN, DROP TABLE, or other destructive operations directly.
- Use the expand-contract pattern:
  1. **Expand**: Deploy new code that stops reading/writing the old column/table
  2. **Contract**: Next deploy: migration drops the column/table

## Dependency Lock Files

- Lock files (Package.resolved, package-lock.json, poetry.lock, etc.) MUST always be committed and in sync with the manifest.
- After any dependency change, regenerate the lock file and commit both together.
