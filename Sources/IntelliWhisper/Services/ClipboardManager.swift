import AppKit
import SwiftyBeaver

/// Manages clipboard writes with undo support and a short history
/// of overwritten items.
@MainActor
final class ClipboardManager {
    private let pasteboard = NSPasteboard.general
    private let maxHistorySize = 5

    /// Items previously on the clipboard that were overwritten by this app.
    private(set) var history: [String] = []

    /// The most recently overwritten clipboard content, used for undo.
    private var previousItem: String?

    /// Copy text to the clipboard. Saves the current clipboard content
    /// to history before overwriting.
    func copy(text: String) {
        // Save whatever is currently on the clipboard
        if let current = pasteboard.string(forType: .string) {
            previousItem = current
            history.insert(current, at: 0)
            if history.count > maxHistorySize {
                history.removeLast()
            }
        } else {
            previousItem = nil
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        log.info("Copied \(text.count) chars to clipboard")
    }

    /// Copy text to the clipboard and immediately simulate Cmd+V to paste it
    /// into the frontmost application. Returns true if the paste was attempted,
    /// false if accessibility permission is missing (copy still succeeds).
    @discardableResult
    func copyAndPaste(text: String) -> Bool {
        copy(text: text)

        guard AXIsProcessTrusted() else {
            log.warning("Accessibility not trusted — paste skipped, text is on clipboard")
            return false
        }

        // Brief delay so the pasteboard is ready before the synthetic keystroke.
        usleep(50_000) // 50 ms

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)   // 'v'
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags   = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)

        log.info("Simulated Cmd+V paste")
        return true
    }

    /// Restore the clipboard content that was overwritten by the last copy().
    func undo() {
        guard let previous = previousItem else {
            log.info("Undo requested but no previous clipboard item")
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(previous, forType: .string)
        previousItem = nil
        log.info("Clipboard undo — restored previous content")
    }
}