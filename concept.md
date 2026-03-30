# Introduction & Goals

The goals of this project is to provide a robust, fully local speech-to-text workflow that preserves user privacy and remains functional without network connectivity. The system will integrate a locally hosted Whisper model via WhisperKit and a local LLM via Ollama in a modular, extensible architecture so that components can be replaced or enhanced with minimal impact on the overall codebase.

Transcribed speech should be processed locally using Ollama for light text cleanup: fixing grammar, punctuation, and removing filler words. The application inspects the active foreground app to detect email context (e.g., Gmail, Outlook, Apple Mail). For email context, Ollama applies full formatting (greeting, closing, professional tone). For all other contexts, the output stays as close to the speaker's original words as possible.

# Technological Requirements

### WhisperKit

Intelliwhisper uses WhisperKit as the speech-to-text engine, running OpenAI's Whisper model locally on macOS via Apple's Core ML. WhisperKit provides highly accurate, on-device transcription with multilingual support (including German) without cloud dependencies, ensuring full privacy and offline functionality.

### Ollama

Intelliwhisper uses Ollama as the local LLM engine for text cleanup. Once WhisperKit produces a raw transcription, Ollama fixes grammar, punctuation, and removes filler words through its REST API (`POST /api/chat` with streaming). For email context, a separate system prompt applies full formatting (greeting, closing, professional tone). The default model is hardware-dependent: `qwen3.5:4b` on machines with 16 GB+ RAM, `qwen3.5:2b` otherwise — configurable in preferences.

### Software delivery

Intelliwhisper must be delivered as a standalone swift desktop app (macOS) capable of running on any ordinary MacBook - the standard workstation at Intellilab.

# Solution Strategy

### Interaction Model

The app uses a **push-to-talk** workflow: the user holds a configurable hotkey (default: Fn/Globe; also Right Option or § key) to record, releases to stop. The result is either copied to the clipboard or auto-pasted into the active app (configurable; auto-paste requires Accessibility permission). A non-activating floating panel provides visual feedback (recording state, processing, result preview) without stealing focus from the target application. A persistent menu bar icon indicates app state and provides access to clipboard history and preferences.

### Processing Pipeline

Four subsystems execute in sequence: **audio capture** (WhisperKit AudioProcessor) → **transcription** (Whisper via Core ML, default: small) → **context detection** (active app identification) → **cleanup** (Ollama LLM via local REST API with streaming — separate system prompts for general and email context, each with few-shot examples). Each subsystem is defined by a Swift protocol, keeping implementations swappable and the pipeline extensible. Formatting can be independently enabled/disabled per context (general and email) in preferences.

### Context Detection

The app identifies the target format by inspecting the foreground application at the moment recording starts. Native email apps are matched by bundle identifier (e.g., Mail, Outlook). For browsers, the window title is parsed to detect webmail (e.g., "Gmail" in the tab title → email). All non-email contexts receive light cleanup only.

### Language & Formality

The default transcription language is German (configurable). The detected language is passed to Ollama so output matches the input language. For German emails, formality defaults to "Sie" unless the speaker explicitly uses "du".

### Distribution & Dependencies

The app is distributed as a non-sandboxed `.pkg` installer (not App Store) to retain access to system APIs required for global hotkey capture and window title reading. The `.pkg` installs a two-app bundle to `/Applications/IntelliWhisper/`: a launcher app and the core app (TCC workaround — see CLAUDE.md for details). Ollama is expected to be installed separately; the app degrades gracefully to raw transcription if Ollama is unavailable.