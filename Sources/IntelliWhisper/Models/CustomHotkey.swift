import CoreGraphics
import Foundation

/// Describes a user-configured push-to-talk hotkey.
/// Stored as JSON in UserDefaults via SettingsService.
struct CustomHotkey: Codable, Equatable, Sendable {

    /// How the hotkey is detected at the CGEvent level.
    enum Kind: String, Codable, Sendable {
        /// Fn (Globe) key — flagsChanged with maskSecondaryFn.
        case fnKey
        /// A single modifier key (e.g. Right Option) — flagsChanged with a specific raw-flag bit.
        case modifier
        /// A regular key, optionally combined with modifiers — keyDown/keyUp with keyCode check.
        case key
    }

    let kind: Kind
    /// Virtual key code (only meaningful for `.key` kind).
    let keyCode: Int64
    /// For `.modifier`: the raw CGEventFlags bit that identifies this specific modifier.
    /// For `.key`: the CGEventFlags mask of required modifier keys (Cmd, Shift, etc.).
    let modifierMask: UInt64
    /// Human-readable label shown in the UI (e.g. "Fn (Globe)", "Right ⌥", "⌘R").
    let displayName: String

    static let `default` = CustomHotkey(
        kind: .fnKey, keyCode: 0, modifierMask: 0, displayName: "Fn (Globe)"
    )

    /// Whether this hotkey is the Fn (Globe) key, which needs special system settings.
    var isFnKey: Bool { kind == .fnKey }

    // MARK: - Migration from legacy HotkeyChoice enum

    static func fromLegacy(_ rawValue: String) -> CustomHotkey? {
        switch rawValue {
        case "fn":
            return .default
        case "rightOption":
            return CustomHotkey(
                kind: .modifier, keyCode: 0,
                modifierMask: 0x00000040, // NX_DEVICERALTKEYMASK
                displayName: "Right ⌥"
            )
        case "sectionSign":
            return CustomHotkey(kind: .key, keyCode: 10, modifierMask: 0, displayName: "§")
        default:
            return nil
        }
    }

    // MARK: - JSON serialization

    func toJSON() -> String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }

    static func fromJSON(_ string: String) -> CustomHotkey? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CustomHotkey.self, from: data)
    }

    /// Reads the current hotkey from a raw UserDefaults string,
    /// handling both legacy enum values and new JSON format.
    static func fromStored(_ raw: String?) -> CustomHotkey {
        guard let raw, !raw.isEmpty else { return .default }
        if let hotkey = fromJSON(raw) { return hotkey }
        if let hotkey = fromLegacy(raw) { return hotkey }
        return .default
    }

    // MARK: - Display name construction

    /// Modifier flags that matter for hotkey matching (ignoring Caps Lock, etc.).
    static let relevantModifierMask: UInt64 =
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue

    /// Device-specific modifier bits for left/right distinction.
    static let deviceModifierBits: [(bit: UInt64, symbol: String)] = [
        (0x00000002, "Left ⇧"),
        (0x00000004, "Right ⇧"),
        (0x00000001, "Left ⌃"),
        (0x00002000, "Right ⌃"),
        (0x00000020, "Left ⌥"),
        (0x00000040, "Right ⌥"),
        (0x00000008, "Left ⌘"),
        (0x00000010, "Right ⌘"),
    ]

    /// Builds a display name from high-level modifier flags and a key name.
    static func buildDisplayName(modifierFlags: UInt64, keyName: String?) -> String {
        var parts: [String] = []
        if modifierFlags & CGEventFlags.maskControl.rawValue != 0 { parts.append("⌃") }
        if modifierFlags & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if modifierFlags & CGEventFlags.maskShift.rawValue != 0 { parts.append("⇧") }
        if modifierFlags & CGEventFlags.maskCommand.rawValue != 0 { parts.append("⌘") }
        if let key = keyName { parts.append(key) }
        return parts.joined()
    }

    /// Maps a virtual key code to a human-readable name.
    /// Pass `characters` from NSEvent.charactersIgnoringModifiers for layout-aware names.
    static func keyName(for keyCode: Int64, characters: String? = nil) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let chars = characters?.uppercased(), !chars.isEmpty,
           let scalar = chars.unicodeScalars.first, scalar.value < 0xF700 {
            return chars
        }
        return "Key \(keyCode)"
    }

    /// Keys with fixed names regardless of keyboard layout.
    private static let specialKeyNames: [Int64: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
        0x41: "Keypad .", 0x43: "Keypad *", 0x45: "Keypad +", 0x47: "Clear",
        0x4B: "Keypad /", 0x4C: "Keypad ↩", 0x4E: "Keypad -",
        0x51: "Keypad =",
        0x52: "Keypad 0", 0x53: "Keypad 1", 0x54: "Keypad 2", 0x55: "Keypad 3",
        0x56: "Keypad 4", 0x57: "Keypad 5", 0x58: "Keypad 6", 0x59: "Keypad 7",
        0x5B: "Keypad 8", 0x5C: "Keypad 9",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3", 0x64: "F8", 0x65: "F9",
        0x67: "F11", 0x69: "F13", 0x6A: "F16", 0x6B: "F14", 0x6D: "F10",
        0x6F: "F12", 0x71: "F15",
        0x73: "Home", 0x74: "Page Up", 0x75: "⌦",
        0x76: "F4", 0x77: "End", 0x78: "F2", 0x79: "Page Down", 0x7A: "F1",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
}
