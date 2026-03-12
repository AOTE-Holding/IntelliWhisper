import AppKit
import Combine
import SwiftUI

/// A non-activating floating panel that displays recording, processing,
/// and result states without stealing keyboard focus from the user's
/// current application.
@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private let orchestrator: PipelineOrchestrator
    private var cancellables = Set<AnyCancellable>()
    private var autoHideTask: Task<Void, Never>?
    private var escapeMonitor: Any?

    /// Preview duration in seconds before auto-hiding the result.
    var previewDuration: TimeInterval = 2.0

    init(orchestrator: PipelineOrchestrator) {
        self.orchestrator = orchestrator
        observeState()
    }

    // MARK: - State observation

    private func observeState() {
        orchestrator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: PipelineState) {
        autoHideTask?.cancel()
        autoHideTask = nil
        removeEscapeMonitor()

        switch state {
        case .idle:
            hidePanel()

        case .recording:
            showPanel()

        case .processing:
            showPanel()

        case .result:
            showPanel()
            installEscapeMonitor()
            // Auto-hide after preview duration
            autoHideTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.previewDuration))
                guard !Task.isCancelled else { return }
                self.removeEscapeMonitor()
                self.orchestrator.dismissResult()
            }

        case .error:
            showPanel()
            // Auto-hide errors after 2 seconds
            autoHideTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.orchestrator.dismissResult()
            }
        }
    }

    // MARK: - Escape-to-undo

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // Escape
            MainActor.assumeIsolated {
                self?.autoHideTask?.cancel()
                self?.autoHideTask = nil
                self?.removeEscapeMonitor()
                self?.orchestrator.undoLastCopy()
                self?.orchestrator.dismissResult()
            }
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Panel management

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let panelView = FloatingPanelView(orchestrator: orchestrator)
        let hostingView = NSHostingController(rootView: panelView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = hostingView
        panel.isReleasedWhenClosed = false

        // Position below menu bar, right-aligned
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 280
            let x = screenFrame.maxX - panelWidth - 16
            let y = screenFrame.maxY - 8
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }
}