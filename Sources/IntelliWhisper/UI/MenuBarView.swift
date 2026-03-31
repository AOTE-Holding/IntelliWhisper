import AppKit
import Combine
import SwiftUI

/// Window subclass that prevents auto-focus on TextFields during initial
/// appearance and resigns TextField focus when clicking empty areas.
final class PreferencesWindow: NSWindow {
    private var suppressInitialFocus = true

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if suppressInitialFocus, responder is NSTextField || responder is NSTextView {
            return false
        }
        return super.makeFirstResponder(responder)
    }

    func enableFocus() {
        suppressInitialFocus = false
    }

    override func mouseDown(with event: NSEvent) {
        suppressInitialFocus = false
        super.mouseDown(with: event)
        if firstResponder is NSTextView {
            makeFirstResponder(contentView)
        }
    }
}

/// Manages the NSStatusItem in the menu bar. Updates the icon based on
/// pipeline state and Ollama availability, and builds the dropdown menu
/// with clipboard history, Preferences, and Quit.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let orchestrator: PipelineOrchestrator
    private var cancellables = Set<AnyCancellable>()
    private var preferencesWindow: NSWindow?

    init(orchestrator: PipelineOrchestrator) {
        self.orchestrator = orchestrator
        setupStatusItem()
        observeState()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "IntelliWhisper")
        button.image?.isTemplate = true

        rebuildMenu()
    }

    // MARK: - State observation

    private func observeState() {
        orchestrator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        orchestrator.$ollamaAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateIcon(for: self.orchestrator.state)
            }
            .store(in: &cancellables)

        orchestrator.$modelReady
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateIcon(for: self.orchestrator.state)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: PipelineState) {
        guard let button = statusItem?.button else { return }

        // Reset tint — let isTemplate handle light/dark adaptation
        button.contentTintColor = nil

        switch state {
        case .recording:
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.image?.isTemplate = true
            button.toolTip = "IntelliWhisper — Recording"
        default:
            if !orchestrator.modelReady {
                button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Loading model")
                button.image?.isTemplate = true
                button.toolTip = "IntelliWhisper — Loading speech model…"
            } else if !orchestrator.ollamaAvailable {
                button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Ollama unavailable")
                button.image?.isTemplate = true
                button.toolTip = "IntelliWhisper — Ready (formatting unavailable)"
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "IntelliWhisper")
                button.image?.isTemplate = true
                button.toolTip = "IntelliWhisper — Ready"
            }
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        // Clipboard history
        let history = orchestrator.clipboard.history
        if !history.isEmpty {
            let headerItem = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            for (index, text) in history.enumerated() {
                let preview = String(text.prefix(50)) + (text.count > 50 ? "…" : "")
                let item = NSMenuItem(title: preview, action: #selector(historyCopy(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit IntelliWhisper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Menu actions

    @objc private func historyCopy(_ sender: NSMenuItem) {
        let index = sender.tag
        let history = orchestrator.clipboard.history
        guard index < history.count else { return }
        orchestrator.clipboard.copy(text: history[index])
    }

    @objc private func openPreferences() {
        if let window = preferencesWindow {
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        let prefsView = PreferencesView(settings: orchestrator.settings, orchestrator: orchestrator)
        let hostingController = NSHostingController(rootView: prefsView)

        let window = PreferencesWindow(contentViewController: hostingController)
        window.title = "IntelliWhisper Preferences"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 400, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.initialFirstResponder = nil

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                window.enableFocus()
            }
        }

        preferencesWindow = window
    }

    @objc private func preferencesWindowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: preferencesWindow
        )
        preferencesWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}