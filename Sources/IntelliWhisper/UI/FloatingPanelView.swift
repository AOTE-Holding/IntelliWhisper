import SwiftUI

/// SwiftUI content for the floating panel. Renders as a Dynamic Island–style
/// dark glass pill that expands and contracts between states.
struct FloatingPanelView: View {
    @ObservedObject var orchestrator: PipelineOrchestrator

    var body: some View {
        Group {
            switch orchestrator.state {
            case .idle:
                EmptyView()

            case .recording(let duration, let audioLevel):
                RecordingView(
                    duration: duration,
                    audioLevel: audioLevel,
                    context: orchestrator.detectedContext,
                    formattingEnabled: orchestrator.detectedContext == .email
                        ? orchestrator.settings.formatEmail
                        : orchestrator.settings.formatGeneral
                )

            case .processing:
                ProcessingView()

            case .result(let output):
                ResultView(output: output)

            case .error(let message):
                ErrorView(message: message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            ZStack {
                VisualEffectBlur()
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: orchestrator.state.discriminator)
    }
}

// MARK: - Subviews

private struct RecordingView: View {
    let duration: TimeInterval
    let audioLevel: Float
    let context: FormatContext
    let formattingEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
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
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)

            WaveformView(audioLevel: audioLevel)
                .frame(maxWidth: .infinity)
                .frame(height: 20)

            ContextIcon(context: context)
            if formattingEnabled {
                FormattingIcon()
            }
        }
        .frame(width: 230)
    }

    private var pulseOpacity: Double { 0.6 }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform

private struct WaveformView: View {
    let audioLevel: Float

    @State private var smoothLevel: CGFloat = 0

    private static let waveColors: [(color: Color, scale: CGFloat, opacity: Double)] = [
        (Color(red: 0, green: 0x62 / 255.0, blue: 0x55 / 255.0), 0.5, 0.45),
        (Color(red: 0, green: 0x78 / 255.0, blue: 0x66 / 255.0), 0.65, 0.55),
        (Color(red: 0, green: 0x98 / 255.0, blue: 0x80 / 255.0), 0.82, 0.7),
        (Color(red: 0, green: 0xBE / 255.0, blue: 0x9A / 255.0), 1.0, 0.9),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let centerY = size.height / 2
                let t = timeline.date.timeIntervalSinceReferenceDate

                for (i, wave) in Self.waveColors.enumerated() {
                    let phaseShift = Double(i) * 0.7
                    let freq = 1.8 + Double(i) * 0.4
                    let phase = t * 2.0 + phaseShift

                    var upper = Path()
                    var lower = Path()
                    upper.move(to: CGPoint(x: 0, y: centerY))
                    lower.move(to: CGPoint(x: 0, y: centerY))

                    for x in stride(from: 0, through: size.width, by: 0.5) {
                        let p = x / size.width
                        let envelope = sin(p * .pi)
                        let amp = centerY * 1.6 * wave.scale * (0.05 + smoothLevel * 0.95) * envelope
                        let sine = sin(phase + p * freq * .pi * 2)

                        upper.addLine(to: CGPoint(x: x, y: centerY + sine * amp))
                        lower.addLine(to: CGPoint(x: x, y: centerY - sine * amp * 0.5))
                    }

                    let style = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    let thinStyle = StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round)

                    context.opacity = wave.opacity
                    context.stroke(upper, with: .color(wave.color), style: style)
                    context.stroke(lower, with: .color(wave.color), style: thinStyle)

                    if i == Self.waveColors.count - 1 {
                        context.opacity = 0.25
                        context.stroke(upper, with: .color(wave.color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        .onChange(of: audioLevel) { _, newLevel in
            let target = CGFloat(min(1.0, max(0, newLevel) * 1.3))
            // Very smooth interpolation — gentle rise and fall
            let weight: CGFloat = target > smoothLevel ? 0.18 : 0.25
            // Cap at 0.6 so amplitude (1.6 * 0.6) never exceeds canvas bounds
            smoothLevel = min(0.6, smoothLevel * (1 - weight) + target * weight)
        }
    }
}

private struct ContextIcon: View {
    let context: FormatContext

    private var iconName: String {
        context == .email ? "envelope.fill" : "text.bubble.fill"
    }

    private var tint: Color { .blue }

    var body: some View {
        Image(systemName: iconName)
            .font(.caption2)
            .foregroundStyle(tint)
            .padding(5)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

private struct FormattingIcon: View {
    var body: some View {
        if let url = Bundle.module.url(forResource: "ollama@2x", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 10)
                .foregroundStyle(.green)
                .padding(5)
                .background(Color.green.opacity(0.15), in: Capsule())
        }
    }
}

private struct ProcessingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Processing…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 160)
    }
}

private struct ResultView: View {
    let output: FormattedOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: output.pasted ? "text.cursor" : "doc.on.clipboard")
                    .foregroundStyle(.green)
                Text(output.pasted ? "Pasted" : "Copied to clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(output.context.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            Text(output.text)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .frame(width: 280)
    }
}

// MARK: - Visual Effect Background

/// NSVisualEffectView with maskImage — the only way to truly round a blur on macOS.
/// CALayer masks (used by .clipShape and .cornerRadius) don't affect CABackdropLayer,
/// which renders the blur via WindowServer. maskImage communicates the shape to
/// WindowServer directly, so the blur itself is clipped to the rounded rect.
private struct VisualEffectBlur: NSViewRepresentable {
    private static let cornerRadius: CGFloat = 22

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.maskImage
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private static let maskImage: NSImage = {
        let r = cornerRadius
        let side = r * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }()
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
                .lineLimit(2)
        }
        .frame(width: 220)
    }
}
