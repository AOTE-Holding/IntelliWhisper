import CoreGraphics
import Foundation
import SwiftyBeaver

/// Captures global hotkey events via CGEventTap for push-to-talk recording.
/// The active hotkey is read from UserDefaults on each event and can be any
/// key or key combination configured by the user via `CustomHotkey`.
/// Requires Input Monitoring permission.
///
/// Publishes four callbacks:
/// - `onRecordStart`: hotkey pressed down
/// - `onRecordStop`:  hotkey released (or hotkey re-pressed while locked)
/// - `onRecordLock`:  L pressed while recording — locks hands-free mode
/// - `onDiscard`:     Escape pressed while hotkey is held (or locked)
///
/// The event tap runs on the main run loop, so all callbacks
/// fire on the main thread.
final class HotkeyManager: @unchecked Sendable {
    nonisolated(unsafe) var onRecordStart: (@MainActor () -> Void)?
    nonisolated(unsafe) var onRecordStop: (@MainActor () -> Void)?
    nonisolated(unsafe) var onRecordLock: (@MainActor () -> Void)?
    nonisolated(unsafe) var onDiscard: (@MainActor () -> Void)?

    /// When true, the hotkey release is ignored and the next hotkey press
    /// fires `onRecordStop`. Set by the orchestrator after `onRecordLock`.
    nonisolated(unsafe) var recordingLocked = false

    /// When true, all events pass through without handling. Set during
    /// hotkey recording in the preferences UI.
    nonisolated(unsafe) var paused = false

    private(set) nonisolated(unsafe) var eventTap: CFMachPort?
    fileprivate nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var hotkeyDown = false
    /// Prevents the key-up after a locked stop from re-triggering onRecordStop.
    private nonisolated(unsafe) var suppressNextKeyUp = false

    /// Currently configured hotkey, read from UserDefaults on each event.
    private var currentHotkey: CustomHotkey {
        CustomHotkey.fromStored(
            UserDefaults.standard.string(forKey: SettingsService.Keys.hotkeyChoice)
        )
    }

    /// Install the global event tap. Returns false if Input Monitoring
    /// permission has not been granted.
    @MainActor
    func start() -> Bool {
        guard CGPreflightListenEventAccess() else {
            log.error("Input Monitoring not granted (preflight check)")
            return false
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: userInfo
        ) else {
            log.error("Event tap creation failed — Input Monitoring permission missing?")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let hotkey = currentHotkey
        log.info("Event tap installed (hotkey=\(hotkey.displayName))")
        return true
    }

    // MARK: - Event handling (called from C callback on main run loop)

    fileprivate func handleEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if paused { return Unmanaged.passUnretained(event) }

        let hotkey = currentHotkey

        // Escape discard + L lock — active while hotkey held or recording locked
        if type == .keyDown && (hotkeyDown || recordingLocked) {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // Escape — discard
                hotkeyDown = false
                recordingLocked = false
                MainActor.assumeIsolated { onDiscard?() }
                return nil
            }
            // L — lock recording (only if L isn't the hotkey itself)
            if keyCode == 37 && hotkeyDown && !recordingLocked {
                if hotkey.kind != .key || hotkey.keyCode != 37 {
                    MainActor.assumeIsolated { onRecordLock?() }
                    return nil
                }
            }
        }

        switch hotkey.kind {
        case .fnKey:
            return handleFnKey(type: type, event: event)
        case .modifier:
            return handleModifier(type: type, event: event, mask: hotkey.modifierMask)
        case .key:
            return handleKey(type: type, event: event, keyCode: hotkey.keyCode, modifiers: hotkey.modifierMask)
        }
    }

    // MARK: - Fn (Globe) key

    private func handleFnKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let pressed = event.flags.contains(.maskSecondaryFn)
        return handleModifierPushToTalk(pressed: pressed, event: event)
    }

    // MARK: - Single modifier key (e.g. Right Option)

    private func handleModifier(type: CGEventType, event: CGEvent, mask: UInt64) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let pressed = (event.flags.rawValue & mask) != 0
        return handleModifierPushToTalk(pressed: pressed, event: event)
    }

    /// Shared push-to-talk logic for modifier-based hotkeys (Fn, Right Option, etc.).
    private func handleModifierPushToTalk(pressed: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        if recordingLocked {
            if pressed {
                hotkeyDown = false
                recordingLocked = false
                MainActor.assumeIsolated { onRecordStop?() }
            }
        } else if pressed && !hotkeyDown {
            hotkeyDown = true
            MainActor.assumeIsolated { onRecordStart?() }
        } else if !pressed && hotkeyDown {
            hotkeyDown = false
            MainActor.assumeIsolated { onRecordStop?() }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Regular key (optionally with modifiers)

    private func handleKey(type: CGEventType, event: CGEvent, keyCode: Int64, modifiers: UInt64) -> Unmanaged<CGEvent>? {
        let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard eventKeyCode == keyCode else { return Unmanaged.passUnretained(event) }

        // For key combos, verify required modifiers are held
        if modifiers != 0 && type == .keyDown {
            let currentMods = event.flags.rawValue & CustomHotkey.relevantModifierMask
            guard currentMods == modifiers else { return Unmanaged.passUnretained(event) }
        }

        if recordingLocked {
            if type == .keyDown && !hotkeyDown {
                // Fresh press (key was released and re-pressed) — stop locked recording
                recordingLocked = false
                suppressNextKeyUp = true
                MainActor.assumeIsolated { onRecordStop?() }
            } else if type == .keyUp {
                // Track release so the next keyDown is recognised as a fresh press
                hotkeyDown = false
            }
            return nil // swallow all events for this key while locked
        }

        if type == .keyDown && !hotkeyDown {
            hotkeyDown = true
            MainActor.assumeIsolated { onRecordStart?() }
            return nil
        } else if type == .keyUp && hotkeyDown {
            hotkeyDown = false
            MainActor.assumeIsolated { onRecordStop?() }
            return nil
        } else if type == .keyUp && suppressNextKeyUp {
            suppressNextKeyUp = false
            return nil
        } else if type == .keyDown && hotkeyDown {
            // Key repeat while held — swallow silently
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}

// MARK: - C callback

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log.warning("Event tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input") — re-enabling")
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type, event: event)
}
