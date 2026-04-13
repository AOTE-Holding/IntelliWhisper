# IntelliWhisper

A macOS menu bar app for fully local, privacy-first speech-to-text. Hold a hotkey to dictate, release to get cleaned-up text on your clipboard — powered by WhisperKit and Ollama, no cloud required.

## Prerequisites

- macOS 14 (Sonoma) or later
- [Ollama](https://ollama.com) installed and running

## Installation

### Building the installer

```bash
./scripts/build.sh --pkg
```

This compiles the app and produces a `.pkg` installer at `.build/IntelliWhisper.pkg`.

### Installing

1. Double-click `IntelliWhisper.pkg` (right-click → **Open** if macOS blocks it).
2. Click through the installer (**Continue** → **Install**).
3. The app launches automatically after installation.
4. Grant permissions when prompted (see below), then relaunch once for **Input Monitoring** to take effect.

To relaunch later, click the **IntelliWhisper** icon in the Dock (added automatically during installation) or open `/Applications/IntelliWhisper/IntelliWhisper.app`.

## Permissions

IntelliWhisper requires several macOS permissions. The app will appear as **IntelliWhisper Core** in System Settings (this is the actual running process; `IntelliWhisper.app` in the Applications folder is a launcher).

If a permission prompt doesn't appear or you accidentally denied it, enable each one manually in **System Settings → Privacy & Security**:

- **Microphone** — required for recording audio.
  Go to **Microphone** → toggle **IntelliWhisper Core** on.
- **Input Monitoring** — required for the push-to-talk hotkey to work globally.
  Go to **Input Monitoring** → add or toggle **IntelliWhisper Core** on. Relaunch the app afterward.
- **Accessibility** — required for auto-paste (simulates Cmd+V after transcription).
  Go to **Accessibility** → add or toggle **IntelliWhisper Core** on.
- **Screen Recording** — required for context detection (reads window titles to adapt formatting).
  Go to **Screen Recording** → add or toggle **IntelliWhisper Core** on.

## Usage

- **Hold** the hotkey (default: Fn/Globe) to record.
- **Release** to stop — the transcription is cleaned up and copied to your clipboard.
- **Press Esc** while recording to discard the recording without copying or pasting.
- Click the **menu bar icon** for clipboard history and preferences.

> **Warning icon in the menu bar:** If you see an exclamation mark (⚠️) instead of the usual waveform icon, Ollama is either not installed or not running. Transcription still works, but text won't be formatted. Start Ollama to restore full functionality.

## Preferences

Click the menu bar icon and select **Preferences** to configure:

- **Language** — transcription language (German, English, or auto-detect).
- **Whisper Model** — speech recognition model size (tiny, base, small, large-v3-turbo). Larger models are more accurate but slower.
- **Ollama Model** — the language model used for formatting transcriptions (e.g. qwen3.5:2b).
- **Hotkey** — the push-to-talk key (Fn/Globe, Right Option, or § key).
- **Output Mode** — clipboard only, or auto-paste into the active field.
- **Formatting** — toggle AI-powered formatting for general transcriptions and emails separately.

## Feedback

- [Report a bug](https://outline.intellilab.ch/doc/bugs-n1BQfQuZCF)
- [Suggest a feature](https://outline.intellilab.ch/doc/future-feature-ideas-jeRXxXPQCW)
