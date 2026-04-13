import Foundation

/// Builds a natural-language prompt from vocabulary lists for WhisperKit's promptTokens.
/// Used by both the UI (token estimation) and the transcriber (actual tokenization).
enum VocabularyPromptBuilder {
    /// Constructs the prompt string. Returns empty string if both lists are empty.
    static func buildPrompt(names: [String], keywords: [String]) -> String {
        var parts: [String] = []
        if !names.isEmpty {
            parts.append("Names: \(names.joined(separator: ", ")).")
        }
        if !keywords.isEmpty {
            parts.append("Keywords: \(keywords.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}
