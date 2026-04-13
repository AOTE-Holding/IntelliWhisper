# IntelliWhisper — Workflow & UX

## Overview

macOS menu bar utility for speech-to-text. Hold hotkey → speak → release → formatted text on clipboard. Runs entirely on-device.

---

## Menu Bar Icon

| State | Appearance |
|-------|------------|
| Loading | Download arrow (WhisperKit model loading) |
| Idle | Monochrome waveform |
| Recording | Filled record circle |
| Ollama unavailable | Warning triangle |

Click to open dropdown: **Clipboard history** (last 5 results, clickable to re-copy) · **Preferences** · **Quit**

---

## Floating Panel

Non-activating — keyboard focus stays in the user's app. Draggable; position persists across launches (reset in Preferences → General).

| State | Shows |
|-------|-------|
| Recording | Pulsing red dot (or lock icon if manually locked), duration timer, context/formatting tags |
| Processing | Progress indicator |
| Result | Formatted text, auto-hides after ~2s. Press Escape to undo clipboard write. |

---

## Core Workflow

1. User holds the hotkey in any app.
2. App detects active window → determines context (email vs general).
3. User speaks; floating panel shows recording state.
4. User releases hotkey → WhisperKit transcribes → Ollama formats → result delivered per output mode.
5. Panel shows result briefly, then hides.

### Hands-free mode

Toggle in Preferences → General. Instead of hold-to-record, press once to start and once to stop. While in hands-free mode, pressing **L** locks recording so the user can freely move hands; a lock icon replaces the pulsing dot.

### Discard

Hold hotkey + press **Escape** to cancel mid-recording. Nothing is transcribed or copied.

---

## Output Modes

| Mode | Behavior |
|------|----------|
| Copy to clipboard | Result copied; user pastes manually |
| Paste directly | Simulates Cmd+V into active app; requires Accessibility permission |
| Paste and keep on clipboard | Both — pastes and keeps result on clipboard |

Clipboard history (last 5 items) is accessible from the menu bar for recovery.

---

## Context Detection

At key-down, the app checks the active app and window title:

| Detected context | Cleanup |
|-----------------|---------|
| Email (Mail.app, Outlook by bundle ID; Gmail, Yahoo Mail, Outlook Web, Proton Mail, etc. by window title) | Full formatting — greeting, closing, professional tone |
| Everything else | Light cleanup — grammar, punctuation, filler word removal |

Detection is automatic and silent.

---

## First-Run Setup Wizard

Steps (auto-skipped if already granted):

1. **Microphone** — required for recording
2. **Screen Recording** — window title reading for context detection (optional)
3. **Input Monitoring** — global hotkey capture
4. **Accessibility** — auto-paste via Cmd+V (optional; only needed for paste output modes)
5. **Hotkey selection** — configure push-to-talk key
6. **Ollama check** — install/start Ollama if needed (skippable)
7. **WhisperKit model download** — ~460 MB, cached locally

After wizard completes the app relaunches so all permissions take effect. If Accessibility is granted later via System Settings, the app detects it and relaunches automatically.

---

## Preferences

- **General:** Language, Whisper model, Hotkey, Output mode, Hands-free recording toggle, Launch at login, Widget position reset
- **Formatting:** Enable/disable formatting per context (general / email); custom system prompts; Ollama model selection
- **Vocabulary:** Custom names and keywords passed to WhisperKit as recognition hints (max ~111 tokens)

---

## Edge Cases

| Situation | Behavior |
|-----------|----------|
| Ollama not running | Raw transcription used; yellow warning icon |
| Recording < 0.5s | Treated as accidental press; ignored |
| No speech detected | Panel shows "No speech detected"; nothing copied |
| Screen Recording denied | Falls back to bundle ID matching only; browser tab detection unavailable |
| Accessibility denied (paste mode) | Falls back to clipboard copy |
