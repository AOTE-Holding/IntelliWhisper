import Foundation
import WhisperKit

/// Records microphone audio using WhisperKit's AudioProcessor.
/// Returns 16kHz mono Float32 samples for transcription.
final class WhisperKitRecorder: AudioRecording, @unchecked Sendable {
    private let processor = AudioProcessor()
    private let minimumDuration: TimeInterval = 0.5
    private var recordingStart: Date?

    /// Current audio input level (0.0–1.0) based on relative energy.
    var audioLevel: Float {
        processor.relativeEnergy.last ?? 0
    }

    /// Begin capturing microphone audio.
    func startRecording() async throws {
        recordingStart = Date()
        try processor.startRecordingLive(inputDeviceID: nil, callback: nil)
    }

    /// Stop capturing and return the recorded audio samples.
    /// Returns an empty array if the recording was shorter than 0.5 seconds.
    func stopRecording() async -> [Float] {
        processor.stopRecording()

        guard let start = recordingStart else { return [] }
        let duration = Date().timeIntervalSince(start)
        recordingStart = nil

        if duration < minimumDuration {
            return []
        }

        return Array(processor.audioSamples)
    }
}