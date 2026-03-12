import SwiftUI

/// SwiftUI content for the floating panel. Switches between recording,
/// processing, result, and error views based on PipelineOrchestrator state.
struct FloatingPanelView: View {
    @ObservedObject var orchestrator: PipelineOrchestrator

    var body: some View {
        Group {
            switch orchestrator.state {
            case .idle:
                EmptyView()

            case .recording(let duration):
                RecordingView(
                    duration: duration,
                    context: orchestrator.detectedContext,
                    formattingEnabled: {
                        let key = orchestrator.detectedContext == .email ? "formatEmail" : "formatGeneral"
                        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
                    }()
                )

            case .processing:
                ProcessingView()

            case .result(let output):
                ResultView(output: output)

            case .error(let message):
                ErrorView(message: message)
            }
        }
        .frame(width: 260)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Subviews

private struct RecordingView: View {
    let duration: TimeInterval
    let context: FormatContext
    let formattingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Pulsing red dot
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseOpacity)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: true
                    )

                Text(formattedDuration)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Recording…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ContextTag(label: context == .email ? "Email" : "General")
                FormattingTag(enabled: formattingEnabled)
            }
        }
    }

    private var pulseOpacity: Double { 0.6 }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ContextTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct FormattingTag: View {
    let enabled: Bool

    var body: some View {
        Text("Formatting")
            .font(.caption2)
            .foregroundStyle(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(enabled ? .green.opacity(0.15) : .clear)
                    .stroke(.green.opacity(0.5), lineWidth: enabled ? 0 : 1)
            )
    }
}

private struct ProcessingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Processing…")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct ResultView: View {
    let output: FormattedOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: output.pasted ? "text.cursor" : "doc.on.clipboard")
                    .foregroundStyle(.green)
                Text(output.pasted ? "Pasted" : "Copied to clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(output.context.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text(output.text)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(.primary)
        }
    }
}

private struct ErrorView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}