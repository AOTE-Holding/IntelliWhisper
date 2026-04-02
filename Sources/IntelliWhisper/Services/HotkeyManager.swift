import CoreGraphics
import Foundation
import SwiftyBeaver

/// Captures global hotkey events via CGEventTap for push-to-talk recording.
/// The active hotkey is configurable via UserDefaults ("hotkeyChoice").
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
    /// Called when the hotkey is pressed down.
    nonisolated(unsafe) var onRecordStart: (@MainActor () -> Void)?
    /// Called when the hotkey is released (or re-pressed to end a locked recording).
    nonisolated(unsafe) var onRecordStop: (@MainActor () -> Void)?
    /// Called when L is pressed during recording to lock hands-free mode.
    nonisolated(unsafe) var onRecordLock: (@MainActor () -> Void)?
    /// Called when Escape is pressed while the hotkey is held or recording is locked.
    nonisolated(unsafe) var onDiscard: (@MainActor () -> Void)?

    /// When true, the hotkey release is ignored and the next hotkey press
    /// fires `onRecordStop`. Set by the orchestrator after `onRecordLock`.
    nonisolated(unsafe) var recordingLocked = false

    private(set) nonisolated(unsafe) var eventTap: CFMachPort?
    fileprivate nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var hotkeyDown = false
    /// Prevents the § key-up after a locked stop from re-triggering onRecordStop.
    private nonisolated(unsafe) var suppressNextKeyUp = false

    /// Currently selected hotkey, read from UserDefaults on each event.
    private var hotkeyChoice: HotkeyChoice {
        HotkeyChoice(rawValue: UserDefaults.standard.string(forKey: SettingsService.Keys.hotkeyChoice) ?? "") ?? .fn
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

        log.info("Event tap installed (hotkey=\(hotkeyChoice.rawValue))")
        return true
    }

    // MARK: - Event handling (called from C callback on main run loop)

    fileprivate func handleEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Escape discard + L lock — active while hotkey held or recording locked
        if type == .keyDown && (hotkeyDown || recordingLocked) {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // Escape — discard
                hotkeyDown = false
                recordingLocked = false
                MainActor.assumeIsolated { onDiscard?() }
                return nil
            }
            if keyCode == 37 && hotkeyDown && !recordingLocked { // L — lock recording
                MainActor.assumeIsolated { onRecordLock?() }
                return nil
            }
        }

        switch hotkeyChoice {
        case .fn:
            return handleFn(type: type, event: event)
        case .rightOption:
            return handleRightOption(type: type, event: event)
        case .sectionSign:
            return handleSectionSign(type: type, event: event)
        }
    }

    // MARK: - Fn (Globe) key

    private func handleFn(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

        let fnPressed = event.flags.contains(.maskSecondaryFn)

        if recordingLocked {
            // Locked: ignore releases. On next press, stop recording.
            if fnPressed {
                hotkeyDown = false
                recordingLocked = false
                MainActor.assumeIsolated { onRecordStop?() }
            }
        } else if fnPressed && !hotkeyDown {
            hotkeyDown = true
            MainActor.assumeIsolated { onRecordStart?() }
        } else if !fnPressed && hotkeyDown {
            hotkeyDown = false
            MainActor.assumeIsolated { onRecordStop?() }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Right Option (⌥)

    /// NX_DEVICERALTKEYMASK — bit set only when the *right* Option key is pressed.
    private static let rightOptionBit: UInt64 = 0x00000040

    private func handleRightOption(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

        let rightOptionPressed = (event.flags.rawValue & Self.rightOptionBit) != 0

        if recordingLocked {
            // Locked: ignore releases. On next press, stop recording.
            if rightOptionPressed {
                hotkeyDown = false
                recordingLocked = false
                MainActor.assumeIsolated { onRecordStop?() }
            }
        } else if rightOptionPressed && !hotkeyDown {
            hotkeyDown = true
            MainActor.assumeIsolated { onRecordStart?() }
        } else if !rightOptionPressed && hotkeyDown {
            hotkeyDown = false
            MainActor.assumeIsolated { onRecordStop?() }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - § key (keyCode 10, ISO keyboards)

    private func handleSectionSign(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 10 else { return Unmanaged.passUnretained(event) }

        if recordingLocked {
            // Locked: on next keyDown, stop recording.
            if type == .keyDown {
                hotkeyDown = false
                recordingLocked = false
                suppressNextKeyUp = true
                MainActor.assumeIsolated { onRecordStop?() }
            }
            return nil // swallow all § events while locked
        }

        if type == .keyDown && !hotkeyDown {
            hotkeyDown = true
            MainActor.assumeIsolated { onRecordStart?() }
            return nil // swallow — don't type §
        } else if type == .keyUp && hotkeyDown {
            hotkeyDown = false
            MainActor.assumeIsolated { onRecordStop?() }
            return nil // swallow release too
        } else if type == .keyUp && suppressNextKeyUp {
            // Swallow the release after a locked stop to prevent re-triggering.
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
