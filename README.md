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

> **Reinstalling or re-running the setup wizard?** Reset everything first, then rebuild:
> ```bash
> ./scripts/build.sh --reset-permissions
> ./scripts/build.sh --pkg
> ```
> This removes the old installation, clears all saved permissions, and resets the setup wizard so it runs fresh on next launch.

### Installing

1. Double-click `IntelliWhisper.pkg` (right-click → **Open** if macOS blocks it).
2. Click through the installer (**Continue** → **Install**).
3. The app launches automatically and the **setup wizard** appears — follow its steps.
4. After the wizard completes, grant every permission that appears, then follow the **Permissions** steps below.

To open the app manually at any time, click the **IntelliWhisper** icon in the Dock or open `/Applications/IntelliWhisper/IntelliWhisper.app`.

## Permissions

IntelliWhisper needs a few macOS permissions to work. Grant them during the setup wizard or add them manually in **System Settings → Privacy & Security**.

> The app appears as **IntelliWhisper Core** in System Settings — that is the correct entry to enable.

**For the best results, follow this exact sequence after installation:**

1. Grant **Microphone**, **Input Monitoring**, and **Screen Recording** when prompted by the wizard or in System Settings.
2. **Quit IntelliWhisper** (click the menu bar icon → **Quit**).
3. **Start IntelliWhisper** again (Dock icon or `/Applications/IntelliWhisper/IntelliWhisper.app`).
4. In **System Settings → Privacy & Security → Accessibility**, enable **IntelliWhisper Core**.
5. **Quit IntelliWhisper** again.
6. **Start IntelliWhisper** one more time — it is now fully set up.

**What each permission does:**

- **Microphone** — records your voice.
- **Input Monitoring** — detects the push-to-talk hotkey globally (works in any app).
- **Accessibility** — pastes the result directly into the active text field (optional but recommended).
- **Screen Recording** — reads the active window title to adapt formatting for emails vs. general text (optional).

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
