import Foundation

/// Available push-to-talk hotkey options.
enum HotkeyChoice: String, CaseIterable, Identifiable {
    case fn = "fn"
    case rightOption = "rightOption"
    case sectionSign = "sectionSign"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: return "Fn (Globe)"
        case .rightOption: return "Right Option (⌥)"
        case .sectionSign: return "§ (left of 1)"
        }
    }

    static var `default`: HotkeyChoice { .fn }
}
