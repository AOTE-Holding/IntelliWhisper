import Foundation

/// Identifies the active application and infers the target format.
protocol ContextDetecting: Sendable {
    /// Inspect the current foreground application and return the appropriate format context.
    func detectContext() -> FormatContext
}