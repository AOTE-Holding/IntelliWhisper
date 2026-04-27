# IntelliWhisper

A macOS menu bar app for fully local, privacy-first speech-to-text. Hold a hotkey to dictate, release to get cleaned-up text on your clipboard — powered by WhisperKit and Ollama, no cloud required.

## Prerequisites

- macOS 14 (Sonoma) or later
- git
- Xcode Command Line Tools: `xcode-select --install`
- [Ollama](https://ollama.com) installed and running (optional — the app falls back to raw transcription without it)

## Install

**Option A — Claude Code:**

Open Claude Code in any directory and run:
```
/intelliwhisper-install
```
The command checks prerequisites, clones the repo to a location of your choice, builds, and installs.

**Option B — Terminal:**

```bash
git clone https://github.com/AOTE-Holding/IntelliWhisper ~/Developer/IntelliWhisper
cd ~/Developer/IntelliWhisper
./scripts/build.sh --release --pkg
open .build/IntelliWhisper.pkg
```

Click **Continue → Install** in the installer. The app launches automatically and the **setup wizard** walks you through permissions, hotkey configuration, and model download.

> **Want to fully uninstall first?** The installer handles permission and wizard resets automatically, so this is only needed if you want to remove the app before rebuilding:
> ```bash
> ./scripts/build.sh --reset-permissions
> ```

## Update

When a new version is available, IntelliWhisper shows a notification in the menu bar. Open the menu and click **Check for Updates…** to see what changed and copy the update commands.

**Option A — Claude Code (from your repo directory):**

```
/intelliwhisper-install
```

**Option B — Terminal (from your repo directory):**

```bash
git pull && ./scripts/build.sh --release --pkg && open .build/IntelliWhisper.pkg
```

Your app settings (hotkey, model, language) are preserved across updates. Permissions are reset on every install — the setup wizard re-runs automatically and guides you through re-granting them.

## Permissions

IntelliWhisper needs a few macOS permissions to work. The setup wizard guides you through each one. You can also grant them manually in **System Settings → Privacy & Security**.

> The app appears as **IntelliWhisper Core** in System Settings — that is the correct entry to enable.

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
