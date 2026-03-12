import Foundation

/// Captures microphone audio into a buffer.
protocol AudioRecording: Sendable {
    /// Begin capturing microphone audio.
    func startRecording() async throws

    /// Stop capturing and return the recorded audio samples (16kHz mono Float32).
    /// Returns an empty array if the recording was shorter than the minimum duration.
    func stopRecording() async -> [Float]

    /// Current audio input level (0.0–1.0) for driving the waveform visualization.
    var audioLevel: Float { get }
}