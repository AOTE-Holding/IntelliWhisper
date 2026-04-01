import Foundation

/// Formats raw transcription text via an LLM.
protocol Formatting: Sendable {
    /// Format the transcription for the given context.
    /// - Parameters:
    ///   - transcription: Raw text from speech-to-text.
    ///   - context: The detected communication context (email, chat, note, general).
    ///   - language: The language of the transcription.
    /// - Returns: An async stream of text chunks (tokens) for progressive display.
    func format(
        transcription: String,
        context: FormatContext,
        language: Language
    ) -> AsyncThrowingStream<String, Error>

    /// Send a minimal request to preload the model into memory.
    func warmup() async

    /// Check whether the LLM backend is reachable and the configured model is available.
    func healthCheck() async -> Bool

    /// Check whether the LLM backend is reachable (ignoring model availability).
    func isReachable() async -> Bool

    /// Pull a model from the backend, streaming progress updates.
    func pullModel(name: String) -> AsyncThrowingStream<PullProgress, Error>

    /// Return the names of all models available on the backend.
    func fetchModels() async -> [String]

    /// Return the backend version string, if available.
    func fetchVersion() async -> String?
}

extension Formatting {
    func fetchVersion() async -> String? { nil }
}