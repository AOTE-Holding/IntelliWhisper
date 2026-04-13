import AppKit
import CoreGraphics
import SwiftUI

/// A button that enters "recording" mode to capture any key or key combination
/// as the push-to-talk hotkey. Writes a JSON-encoded `CustomHotkey` to the binding.
///
/// Supports three capture modes:
/// - **Regular key** (with optional modifiers): captured on keyDown
/// - **Modifier-only** (e.g. Right Option): captured when all modifiers are released
///   without a keyDown in between
/// - **Fn (Globe)**: captured via the `.function` flag on flagsChanged
struct HotkeyRecorderView: View {
    @Binding var hotkeyJSON: String
    /// Called when recording starts/stops so the caller can pause the HotkeyManager.
    var onRecordingChanged: ((Bool) -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pendingModifiers: UInt64 = 0
    @State private var pendingFn = false
    @State private var displayName: String = ""

    private var label: String {
        if isRecording { return "Press a key…" }
        if displayName.isEmpty { return "Unknown key" }
        return displayName
    }

    var body: some View {
        Button(action: toggleRecording) {
            Text(label)
                .foregroundStyle(isRecording ? .blue : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 60)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onAppear { updateDisplayName() }
        .onChange(of: hotkeyJSON) { _, _ in updateDisplayName() }
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording lifecycle

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        pendingModifiers = 0
        pendingFn = false
        onRecordingChanged?(true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                handleKeyDown(event)
            } else if event.type == .flagsChanged {
                handleFlagsChanged(event)
            }
            return nil // swallow all events while recording
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingModifiers = 0
        pendingFn = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onRecordingChanged?(false)
    }

    // MARK: - Event handling

    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)

        // Escape cancels recording without changing the hotkey
        if keyCode == 0x35 {
            stopRecording()
            return
        }

        // Get modifier flags (strip Fn flag — it's ambiguous for function keys)
        let rawFlags = event.cgEvent?.flags.rawValue ?? 0
        let modifiers = rawFlags & CustomHotkey.relevantModifierMask

        let characters = event.charactersIgnoringModifiers
        let keyName = CustomHotkey.keyName(for: keyCode, characters: characters)
        let name = modifiers != 0
            ? CustomHotkey.buildDisplayName(modifierFlags: modifiers, keyName: keyName)
            : keyName

        let hotkey = CustomHotkey(
            kind: .key, keyCode: keyCode, modifierMask: modifiers, displayName: name
        )
        hotkeyJSON = hotkey.toJSON()
        stopRecording()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent else { return }
        let rawFlags = cgEvent.flags.rawValue

        // Check for Fn (Globe) key
        let fnDown = cgEvent.flags.contains(.maskSecondaryFn)
        if fnDown && !pendingFn && pendingModifiers == 0 {
            pendingFn = true
            return
        }
        if !fnDown && pendingFn {
            // Fn released without any other key — capture as Fn hotkey
            let hotkey = CustomHotkey.default
            hotkeyJSON = hotkey.toJSON()
            stopRecording()
            return
        }

        // Check device-specific modifier bits
        var deviceBits: UInt64 = 0
        for (bit, _) in CustomHotkey.deviceModifierBits {
            if rawFlags & bit != 0 { deviceBits |= bit }
        }

        if deviceBits != 0 {
            // New modifier pressed
            pendingModifiers = deviceBits
            pendingFn = false
        } else if pendingModifiers != 0 {
            // All modifiers released — capture as modifier-only hotkey
            captureModifier()
        }
    }

    private func captureModifier() {
        let mask = pendingModifiers
        pendingModifiers = 0

        // Find the first matching device-specific modifier
        for (bit, symbol) in CustomHotkey.deviceModifierBits {
            if mask & bit != 0 {
                let hotkey = CustomHotkey(
                    kind: .modifier, keyCode: 0, modifierMask: bit, displayName: symbol
                )
                hotkeyJSON = hotkey.toJSON()
                stopRecording()
                return
            }
        }
    }

    // MARK: - Display

    private func updateDisplayName() {
        if let hotkey = CustomHotkey.fromJSON(hotkeyJSON) {
            displayName = hotkey.displayName
        } else if let hotkey = CustomHotkey.fromLegacy(hotkeyJSON) {
            displayName = hotkey.displayName
        } else {
            displayName = CustomHotkey.default.displayName
        }
    }
}
