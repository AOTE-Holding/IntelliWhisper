import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation

/// Drives the first-run onboarding wizard. Each step triggers a permission
/// prompt or prerequisite check. The view observes published properties to
/// update the UI.
@MainActor
final class FirstRunCoordinator: ObservableObject {

    // MARK: - Step model

    enum Step: Int, CaseIterable, Sendable {
        case microphone
        case screenRecording
        case inputMonitoring
        case hotkeySelection
        case ollama
        case modelDownload
    }

    enum StepStatus: Sendable {
        case pending
        case inProgress
        case granted
        case skipped
        case failed(String)
    }

    // MARK: - Published state

    @Published private(set) var currentStep: Step = .microphone
    @Published private(set) var stepStatuses: [Step: StepStatus] = {
        var dict = [Step: StepStatus]()
        for step in Step.allCases { dict[step] = .pending }
        return dict
    }()
    @Published var isComplete = false

    /// Progress of an Ollama model pull (0.0–1.0), nil when not pulling.
    @Published private(set) var pullProgress: Double?
    /// Status text during an Ollama model pull.
    @Published private(set) var pullStatus: String?

    // MARK: - Subsystems

    let settings: SettingsService
    private let transcriber: any Transcribing
    private let formatter: any Formatting
    private let hotkey: HotkeyManager
    private let orchestrator: PipelineOrchestrator

    init(
        settings: SettingsService,
        transcriber: any Transcribing,
        formatter: any Formatting,
        hotkey: HotkeyManager,
        orchestrator: PipelineOrchestrator
    ) {
        self.settings = settings
        self.transcriber = transcriber
        self.formatter = formatter
        self.hotkey = hotkey
        self.orchestrator = orchestrator
    }

    // MARK: - Auto-advance past already-granted permissions

    /// Check which permissions are already granted and skip past them.
    /// Called when the wizard appears (handles restart-after-grant scenarios).
    func autoAdvancePastGranted() async {
        // Microphone
        if currentStep == .microphone {
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
            if micGranted {
                stepStatuses[.microphone] = .granted
                advance()
            } else {
                return
            }
        }

        // Screen Recording
        if currentStep == .screenRecording {
            let screenGranted: Bool
            if #available(macOS 15, *) {
                screenGranted = CGPreflightScreenCaptureAccess()
            } else {
                screenGranted = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) != nil
            }
            if screenGranted {
                stepStatuses[.screenRecording] = .granted
                advance()
            } else {
                return
            }
        }

        // Input Monitoring
        if currentStep == .inputMonitoring {
            if CGPreflightListenEventAccess() {
                stepStatuses[.inputMonitoring] = .granted
                advance()
            } else {
                return
            }
        }

        // Hotkey — auto-confirm if previously configured
        if currentStep == .hotkeySelection {
            if settings.hotkeyWasPreviouslyConfigured {
                stepStatuses[.hotkeySelection] = .granted
                advance()
            } else {
                return
            }
        }
    }

    // MARK: - Step actions

    func requestMicrophone() async {
        stepStatuses[.microphone] = .inProgress
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if granted {
            stepStatuses[.microphone] = .granted
        } else {
            stepStatuses[.microphone] = .failed(
                "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
            )
        }
    }

    func requestScreenRecording() {
        stepStatuses[.screenRecording] = .inProgress
        // CGRequestScreenCaptureAccess triggers the system prompt (macOS 15+).
        // On older macOS, calling CGWindowListCopyWindowInfo has the same effect.
        if #available(macOS 15, *) {
            CGRequestScreenCaptureAccess()
        } else {
            _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        }
        // macOS doesn't return the result synchronously — the user must
        // grant access in System Settings and restart the app for it to
        // take effect. Mark as granted optimistically; AppInitializer
        // will catch real failures on subsequent launches.
        stepStatuses[.screenRecording] = .granted
    }

    func requestInputMonitoring() {
        stepStatuses[.inputMonitoring] = .inProgress

        if CGPreflightListenEventAccess() {
            stepStatuses[.inputMonitoring] = .granted
        } else {
            CGRequestListenEventAccess()
            stepStatuses[.inputMonitoring] = .failed(
                "Input Monitoring required. Add IntelliWhisper in System Settings → Privacy & Security → Input Monitoring, then restart the app."
            )
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func confirmHotkey() {
        stepStatuses[.hotkeySelection] = .granted
    }

    func checkOllama() async {
        stepStatuses[.ollama] = .inProgress

        // 1. Check if Ollama is running
        guard await formatter.isReachable() else {
            stepStatuses[.ollama] = .failed(
                "Ollama not reachable. Install it and run `ollama serve`, then retry."
            )
            return
        }

        // 2. Check if the default model is already pulled
        await orchestrator.checkOllamaHealth()
        if orchestrator.ollamaAvailable {
            stepStatuses[.ollama] = .granted
            return
        }

        // 3. Model missing — auto-pull
        await pullDefaultModel()
    }

    private func pullDefaultModel() async {
        let modelName = SettingsService.defaultOllamaModel
        pullStatus = "Pulling \(modelName)…"
        pullProgress = 0

        do {
            let stream = formatter.pullModel(name: modelName)
            for try await progress in stream {
                pullStatus = progress.status
                if let completed = progress.completed, let total = progress.total, total > 0 {
                    pullProgress = Double(completed) / Double(total)
                }
            }

            // Verify the model is now available
            await orchestrator.checkOllamaHealth()
            pullProgress = nil
            pullStatus = nil
            if orchestrator.ollamaAvailable {
                stepStatuses[.ollama] = .granted
            } else {
                let version = await formatter.fetchVersion()
                let versionHint = version.map { " Your Ollama version is \($0) — this model may require a newer version. Run `brew upgrade ollama` and retry." } ?? ""
                stepStatuses[.ollama] = .failed("Model \(modelName) was pulled but not found.\(versionHint)")
            }
        } catch {
            pullProgress = nil
            pullStatus = nil
            stepStatuses[.ollama] = .failed("Failed to pull model: \(error.localizedDescription)")
        }
    }

    func downloadModel() async {
        stepStatuses[.modelDownload] = .inProgress
        do {
            let modelName = settings.whisperModel
            let model = WhisperModel(rawValue: modelName) ?? .default
            try await transcriber.setup(model: model)
            orchestrator.modelReady = true
            stepStatuses[.modelDownload] = .granted
        } catch {
            stepStatuses[.modelDownload] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Navigation

    func advance() {
        guard let current = Step(rawValue: currentStep.rawValue + 1) else {
            finish()
            return
        }
        currentStep = current
    }

    func skip() {
        stepStatuses[currentStep] = .skipped
        advance()
    }

    func finish() {
        settings.setupCompleted = true
        isComplete = true
    }
}
