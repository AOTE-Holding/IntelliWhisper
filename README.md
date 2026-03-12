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
4. Grant **Accessibility** and **Microphone** permissions when prompted, then relaunch once for **Input Monitoring** to take effect.

To relaunch later, open `/Applications/IntelliWhisper/Start IntelliWhisper.app`.

## Granting permissions manually

If a permission prompt doesn't appear or you accidentally denied it, you can enable each one manually in **System Settings → Privacy & Security**:

- **Microphone**: Go to **Privacy & Security → Microphone** → toggle **IntelliWhisper** on.
- **Input Monitoring**: Go to **Privacy & Security → Input Monitoring** → add or toggle **IntelliWhisper** on. Relaunch the app afterward.
- **Accessibility**: Go to **Privacy & Security → Accessibility** → add or toggle **IntelliWhisper** on. This is needed for the auto-paste feature.

## Usage

- **Hold** the hotkey (default: Fn/Globe) to record.
- **Release** to stop — the transcription is cleaned up and copied to your clipboard.
- Click the **menu bar icon** for clipboard history and preferences.
