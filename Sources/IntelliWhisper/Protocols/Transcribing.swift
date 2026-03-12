import Foundation

/// Converts audio samples into text.
protocol Transcribing: Sendable {
    /// Prepare the transcriber (e.g. download and load models).
    /// Must be called before transcribe().
    func setup(model: WhisperModel) async throws

    /// Switch to a different model at runtime.
    /// Releases the current model and loads the new one.
    func switchModel(_ model: WhisperModel) async throws

    /// Transcribe the given audio buffer.
    /// - Parameters:
    ///   - audio: 16kHz mono Float32 samples.
    ///   - language: Preferred language, or nil for auto-detection.
    /// - Returns: The transcription result with text and detected language.
    func transcribe(audio: [Float], language: Language?) async throws -> Transcription
}