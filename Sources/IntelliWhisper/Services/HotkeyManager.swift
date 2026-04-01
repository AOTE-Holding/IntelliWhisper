import CoreGraphics
import Foundation
import SwiftyBeaver

/// Captures global hotkey events via CGEventTap for push-to-talk recording.
/// The active hotkey is configurable via UserDefaults ("hotkeyChoice").
/// Requires Input Monitoring permission.
///
/// Publishes three callbacks:
/// - `onRecordStart`: hotkey pressed down
/// - `onRecordStop`:  hotkey released
/// - `onDiscard`:     Escape pressed while hotkey is held
///
/// The event tap runs on the main run loop, so all callbacks
/// fire on the main thread.
final class HotkeyManager: @unchecked Sendable {
    /// Called when the hotkey is pressed down.
    nonisolated(unsafe) var onRecordStart: (@MainActor () -> Void)?
    /// Called when the hotkey is released.
    nonisolated(unsafe) var onRecordStop: (@MainActor () -> Void)?
    /// Called when Escape is pressed while the hotkey is held.
    nonisolated(unsafe) var onDiscard: (@MainActor () -> Void)?

    private(set) nonisolated(unsafe) var eventTap: CFMachPort?
    fileprivate nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var hotkeyDown = false

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
        // Escape discard — always active regardless of hotkey choice
        if type == .keyDown && hotkeyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // Escape
                hotkeyDown = false
                MainActor.assumeIsolated { onDiscard?() }
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

        if fnPressed && !hotkeyDown {
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

        if rightOptionPressed && !hotkeyDown {
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

        if type == .keyDown && !hotkeyDown {
            hotkeyDown = true
            MainActor.assumeIsolated { onRecordStart?() }
            return nil // swallow — don't type §
        } else if type == .keyUp && hotkeyDown {
            hotkeyDown = false
            MainActor.assumeIsolated { onRecordStop?() }
            return nil // swallow release too
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
