import SwiftUI

/// Step-by-step onboarding wizard shown on first launch.
/// Guides the user through permissions, Fn key setup, Ollama check,
/// and WhisperKit model download.
struct FirstRunView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Welcome to IntelliWhisper")
                    .font(.title2.bold())

                Text("Let's set up a few things before you start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Step indicator
            StepIndicator(
                steps: FirstRunCoordinator.Step.allCases,
                current: coordinator.currentStep,
                statuses: coordinator.stepStatuses
            )
            .padding(.bottom, 20)

            Divider()

            // Step content
            ScrollView {
                stepContent
                    .padding(24)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Bottom bar
            HStack {
                if canSkip {
                    Button("Skip") {
                        coordinator.skip()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if canContinue && coordinator.currentStep != .modelDownload {
                    Button("Continue") {
                        coordinator.advance()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - Step routing

    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.currentStep {
        case .microphone:
            MicrophoneStepView(coordinator: coordinator)
        case .screenRecording:
            ScreenRecordingStepView(coordinator: coordinator)
        case .inputMonitoring:
            InputMonitoringStepView(coordinator: coordinator)
        case .hotkeySelection:
            HotkeySelectionStepView(coordinator: coordinator)
        case .ollama:
            OllamaStepView(coordinator: coordinator)
        case .modelDownload:
            ModelDownloadStepView(coordinator: coordinator)
        }
    }

    private var currentStatus: FirstRunCoordinator.StepStatus {
        coordinator.stepStatuses[coordinator.currentStep] ?? .pending
    }

    private var canContinue: Bool {
        switch currentStatus {
        case .granted, .skipped: return true
        case .failed:
            // Allow continuing past failures that require an app restart
            // or are non-critical. Only model download truly blocks.
            return coordinator.currentStep != .modelDownload
        default: return false
        }
    }

    private var canSkip: Bool {
        coordinator.currentStep == .ollama
    }
}

// MARK: - Step indicator

private struct StepIndicator: View {
    let steps: [FirstRunCoordinator.Step]
    let current: FirstRunCoordinator.Step
    let statuses: [FirstRunCoordinator.Step: FirstRunCoordinator.StepStatus]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps, id: \.rawValue) { step in
                Circle()
                    .fill(color(for: step))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func color(for step: FirstRunCoordinator.Step) -> Color {
        if step == current { return .blue }
        switch statuses[step] {
        case .granted: return .green
        case .skipped: return .gray
        case .failed: return .orange
        default: return .gray.opacity(0.3)
        }
    }
}

// MARK: - Step views

private struct MicrophoneStepView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        StepLayout(
            icon: "mic.fill",
            title: "Microphone Access",
            description: "IntelliWhisper needs microphone access to record your voice for transcription. Audio is processed entirely on-device — nothing is sent to the cloud."
        ) {
            StepActionButton(
                status: coordinator.stepStatuses[.microphone] ?? .pending,
                label: "Grant Access"
            ) {
                Task { await coordinator.requestMicrophone() }
            }
        }
    }
}

private struct ScreenRecordingStepView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        StepLayout(
            icon: "rectangle.on.rectangle",
            title: "Screen Recording",
            description: "This permission lets IntelliWhisper read window titles to detect whether you're in an email, chat, or notes app. It does NOT record your screen — it only reads the title of the active window."
        ) {
            StepActionButton(
                status: coordinator.stepStatuses[.screenRecording] ?? .pending,
                label: "Grant Access"
            ) {
                coordinator.requestScreenRecording()
            }

            if case .granted = coordinator.stepStatuses[.screenRecording] {
                Text("You may need to restart the app for this to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

private struct InputMonitoringStepView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        StepLayout(
            icon: "keyboard",
            title: "Input Monitoring",
            description: "IntelliWhisper uses a push-to-talk key to start and stop recording. Input Monitoring permission is required to detect key presses globally."
        ) {
            StepActionButton(
                status: coordinator.stepStatuses[.inputMonitoring] ?? .pending,
                label: "Grant Access"
            ) {
                coordinator.requestInputMonitoring()
            }

            if case .failed = coordinator.stepStatuses[.inputMonitoring] {
                Button("Open System Settings") {
                    coordinator.openInputMonitoringSettings()
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)

                Text("Add IntelliWhisper in Input Monitoring, then quit and relaunch the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

private struct HotkeySelectionStepView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    private var isConfirmed: Bool {
        guard case .granted = coordinator.stepStatuses[.hotkeySelection] else { return false }
        return true
    }

    private var currentHotkey: CustomHotkey {
        CustomHotkey.fromStored(coordinator.settings.hotkeyChoice)
    }

    var body: some View {
        StepLayout(
            icon: "keyboard",
            title: "Push-to-Talk Key",
            description: "Choose which key or key combination starts and stops recording. Press and hold to record, release to stop."
        ) {
            if isConfirmed {
                Label("Set to: \(currentHotkey.displayName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)

                if currentHotkey.isFnKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Go to:")
                            .font(.callout.bold())
                        Text("System Settings → Keyboard → \"Press fn key to\" → \"Do Nothing\"")
                            .font(.callout)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Record a different key:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    hotkeyRecorder
                }
                .padding(.top, 4)
            } else {
                if coordinator.settings.hotkeyWasPreviouslyConfigured {
                    Button("Keep current: \(currentHotkey.displayName)") {
                        coordinator.confirmHotkey()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Use default (Fn)") {
                        coordinator.confirmHotkey()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(coordinator.settings.hotkeyWasPreviouslyConfigured
                    ? "Or record a different key:"
                    : "Or record a custom key:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                hotkeyRecorder
            }

            Text("You can change this later in Preferences.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private var hotkeyRecorder: some View {
        HotkeyRecorderView(hotkeyJSON: Binding(
            get: { coordinator.settings.hotkeyChoice },
            set: { newValue in
                coordinator.settings.hotkeyChoice = newValue
                coordinator.confirmHotkey()
            }
        ))
    }
}

private struct OllamaStepView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        StepLayout(
            icon: "server.rack",
            title: "Ollama (Optional)",
            description: "Ollama is a local AI runtime that formats your transcriptions (punctuation, capitalization, structure). Without it, you'll get raw unformatted text. The app works either way."
        ) {
            if let progress = coordinator.pullProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)

                    Text(coordinator.pullStatus ?? "Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                StepActionButton(
                    status: coordinator.stepStatuses[.ollama] ?? .pending,
                    label: "Check Connection"
                ) {
                    Task { await coordinator.checkOllama() }
                }
            }

            if case .failed = coordinator.stepStatuses[.ollama] {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To install Ollama, run in Terminal:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("brew install ollama")
                        Text("ollama serve")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Text("You can skip this and set it up later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct ModelDownloadStepView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        StepLayout(
            icon: "arrow.down.circle",
            title: "Download Speech Model",
            description: "IntelliWhisper uses OpenAI's Whisper model for on-device speech recognition. The default model (Small, ~460 MB) needs to be downloaded once."
        ) {
            switch coordinator.stepStatuses[.modelDownload] {
            case .inProgress:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Downloading and loading model…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("This may take a few minutes on first launch.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)

            case .granted:
                Label("Model ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)

                Button("Finish Setup") {
                    coordinator.finish()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)

                Button("Retry") {
                    Task { await coordinator.downloadModel() }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)

            default:
                Button("Download Model (~460 MB)") {
                    Task { await coordinator.downloadModel() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Reusable layout

private struct StepLayout<Actions: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                Text(title)
                    .font(.headline)
            }

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StepActionButton: View {
    let status: FirstRunCoordinator.StepStatus
    let label: String
    let action: () -> Void

    var body: some View {
        switch status {
        case .pending:
            Button(label, action: action)
                .buttonStyle(.borderedProminent)

        case .inProgress:
            ProgressView()
                .controlSize(.small)

        case .granted:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)

                Button("Retry", action: action)
                    .buttonStyle(.bordered)
            }

        case .skipped:
            Text("Skipped")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
