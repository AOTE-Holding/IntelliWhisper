import AppKit
import Combine
import SwiftUI

/// A non-activating floating panel that displays recording, processing,
/// and result states without stealing keyboard focus from the user's
/// current application. Styled as a Dynamic Island pill centered below
/// the menu bar.
@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private let orchestrator: PipelineOrchestrator
    private let settings: SettingsService
    private var cancellables = Set<AnyCancellable>()
    private var autoHideTask: Task<Void, Never>?
    private var escapeMonitor: Any?
    private var isHiding = false

    /// Preview duration in seconds before auto-hiding the result.
    var previewDuration: TimeInterval = 2.0

    init(orchestrator: PipelineOrchestrator, settings: SettingsService) {
        self.orchestrator = orchestrator
        self.settings = settings
        observeState()
        observePositionReset()
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
            // Panel was already faded out by animateDismiss() in the normal flow.
            // Guard against edge cases where state is set externally.
            if panel?.isVisible == true {
                panel?.orderOut(nil)
            }

        case .recording:
            showPanel()

        case .processing:
            showPanel()

        case .result:
            showPanel()
            installEscapeMonitor()
            autoHideTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.previewDuration))
                guard !Task.isCancelled else { return }
                self.animateDismiss()
            }

        case .error:
            showPanel()
            autoHideTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.animateDismiss()
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
                self?.orchestrator.undoLastCopy()
                self?.animateDismiss()
            }
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Position reset observation

    private func observePositionReset() {
        settings.$panelPosition
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self, let panel = self.panel as? TopAnchoredPanel else { return }
                if newValue == nil {
                    panel.useCustomPosition = false
                    panel.customTopLeft = nil
                    self.centerPanel(panel)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel management

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        isHiding = false

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Smoothly fades the panel out, then dismisses the pipeline state.
    /// Content stays frozen during the fade so nothing collapses visibly.
    private func animateDismiss() {
        removeEscapeMonitor()
        guard let panel, panel.isVisible, !isHiding else {
            orchestrator.dismissResult()
            return
        }
        isHiding = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.panel?.orderOut(nil)
                self.isHiding = false
                self.orchestrator.dismissResult()
            }
        })
    }

    private func createPanel() {
        let panelView = FloatingPanelView(orchestrator: orchestrator)
        let hostingController = NSHostingController(rootView: panelView)
        hostingController.sizingOptions = .preferredContentSize
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = TopAnchoredPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController

        // Load saved position or center below menu bar
        if let savedPoint = settings.panelPositionPoint, isPointOnScreen(savedPoint) {
            panel.useCustomPosition = true
            panel.customTopLeft = savedPoint
            panel.setFrameTopLeftPoint(savedPoint)
        } else {
            settings.resetPanelPosition()
            centerPanel(panel)
        }

        panel.onPositionChanged = { [weak self] topLeft in
            self?.settings.savePanelPosition(topLeft)
        }

        self.panel = panel
    }

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = visibleFrame.origin.x + (visibleFrame.width - panelFrame.width) / 2
        let y = visibleFrame.maxY - 4
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func isPointOnScreen(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            screen.frame.contains(point)
        }
    }
}

// MARK: - Top-anchored panel

/// NSPanel subclass that keeps its top edge fixed when the content resizes
/// and supports drag-to-reposition.
private class TopAnchoredPanel: NSPanel {
    var useCustomPosition = false
    var customTopLeft: NSPoint?
    var onPositionChanged: ((NSPoint) -> Void)?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isMovableByWindowBackground = true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard isVisible else {
            super.setFrame(frameRect, display: flag)
            return
        }
        var rect = frameRect
        // Keep top edge pinned: adjust origin so maxY stays the same
        rect.origin.y = frame.maxY - rect.height

        if useCustomPosition, let custom = customTopLeft {
            // Pin to custom x position
            rect.origin.x = custom.x
        } else {
            // Default: center horizontally
            if let screen = screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                rect.origin.x = visible.origin.x + (visible.width - rect.width) / 2
            }
        }
        super.setFrame(rect, display: flag)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let topLeft = NSPoint(x: frame.origin.x, y: frame.maxY)
        customTopLeft = topLeft
        useCustomPosition = true
        onPositionChanged?(topLeft)
    }
}
