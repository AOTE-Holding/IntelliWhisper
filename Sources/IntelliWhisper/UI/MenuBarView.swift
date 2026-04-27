import AppKit
import Combine
import SwiftUI

private final class AlertButtonProxy: NSObject {
    private let text: String
    init(text: String) { self.text = text }

    @MainActor @objc func copyToClipboard(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let original = sender.title
        sender.title = "Copied!"
        sender.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak sender] in
            sender?.title = original
            sender?.isEnabled = true
        }
    }
}

/// Panel subclass that prevents auto-focus on TextFields during initial
/// appearance and resigns TextField focus when clicking empty areas.
/// NSPanel is used instead of NSWindow so the panel can become key
/// even when the app is in accessory (menu-bar-only) activation mode.
final class PreferencesWindow: NSPanel {
    private var suppressInitialFocus = true

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
        NSApp.activate()
        super.mouseDown(with: event)
        if firstResponder is NSTextView {
            _ = makeFirstResponder(contentView)
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
    private let updateService = UpdateService()

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
            } else if !orchestrator.ollamaAvailable &&
                      (orchestrator.settings.formatGeneral || orchestrator.settings.formatEmail) {
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

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesMenuAction), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

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
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let prefsView = PreferencesView(settings: orchestrator.settings, orchestrator: orchestrator)
        let hostingController = NSHostingController(rootView: prefsView)

        let window = PreferencesWindow(contentViewController: hostingController)
        window.title = "IntelliWhisper Preferences"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 400, height: 580))
        window.center()
        window.isReleasedWhenClosed = false
        window.initialFirstResponder = nil

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        setDockIcon()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            window.enableFocus()
        }

        preferencesWindow = window
    }

    /// Sets the Dock tile icon to IntelliWhisper.icns so the Dock shows
    /// the real app icon instead of a generic "exec" tile.
    private func setDockIcon() {
        let iconName = "IntelliWhisper.icns"
        let searchRoots: [URL] = [
            // Production: app bundle Resources/
            Bundle.main.resourceURL,
            // Development (swift run): current working directory + Resources/
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources"),
            // Development: walk up from executable
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        for root in searchRoots {
            let candidate = root.appendingPathComponent(iconName)
            if let icon = NSImage(contentsOfFile: candidate.path) {
                NSApp.applicationIconImage = icon
                let imageView = NSImageView(image: icon)
                NSApp.dockTile.contentView = imageView
                NSApp.dockTile.display()
                return
            }
        }
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

    @objc private func checkForUpdatesMenuAction() {
        Task { await performUpdateCheck(silent: false) }
    }

    func performUpdateCheck(silent: Bool) async {
        guard let result = await updateService.checkForUpdates(silent: silent) else {
            if !silent {
                let alert = NSAlert()
                alert.messageText = "Could not check for updates."
                alert.informativeText = "Make sure you're connected to the internet and running IntelliWhisper from the app bundle, not a debug binary."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                showAlert(alert)
            }
            return
        }

        switch result {
        case .upToDate(let current, let remote):
            guard !silent else { return }
            let alert = NSAlert()
            alert.messageText = "You're up to date."
            alert.informativeText = "You're on version \(current), which is the latest\(current == remote ? "." : " (latest: \(remote)).")"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            showAlert(alert)

        case .updateAvailable(let info):
            let commands = "git pull\n./scripts/build.sh --release --pkg\nopen .build/IntelliWhisper.pkg"
            let alert = NSAlert()
            alert.messageText = "IntelliWhisper v\(info.version) is available."
            alert.informativeText = """
                You're on version \(currentVersion()).

                Run the following from your IntelliWhisper repo directory to update:

                    \(commands.replacingOccurrences(of: "\n", with: "\n    "))

                Or run /intelliwhisper-install in Claude Code.

                Note: the setup wizard will re-run after the update to re-grant permissions.
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Copy Commands")
            alert.addButton(withTitle: "Later")
            if !info.releaseNotes.isEmpty {
                alert.accessoryView = makeNotesView(info.releaseNotes)
            }
            let proxy = AlertButtonProxy(text: commands)
            alert.buttons[0].target = proxy
            alert.buttons[0].action = #selector(AlertButtonProxy.copyToClipboard(_:))
            showAlert(alert)
        }
    }

    @discardableResult
    private func showAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        return response
    }

    private func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func makeNotesView(_ markdown: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textStorage?.setAttributedString(renderMarkdown(markdown))

        scrollView.documentView = textView
        return scrollView
    }

    private func renderMarkdown(_ markdown: String) -> NSAttributedString {
        let bodyFont  = NSFont.systemFont(ofSize: 12)
        let h2Font    = NSFont.boldSystemFont(ofSize: 14)
        let h3Font    = NSFont.boldSystemFont(ofSize: 12)
        let monoFont  = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let label     = NSColor.labelColor
        let codeBg    = NSColor(white: 0.5, alpha: 0.12)

        let normalPara: NSParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = 3
            return p
        }()
        let headingPara: NSParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = 10
            p.paragraphSpacing = 3
            return p
        }()
        let listPara: NSParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.headIndent = 12
            p.paragraphSpacing = 1
            return p
        }()

        let out = NSMutableAttributedString()

        // Appends plain text with given attributes.
        func plain(_ text: String, font: NSFont, para: NSParagraphStyle) {
            out.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: label, .paragraphStyle: para
            ]))
        }

        // Appends a line that may contain `code` and **bold** spans.
        func inline(_ text: String, baseFont: NSFont, para: NSParagraphStyle, prefix: String = "") {
            let line = NSMutableAttributedString()
            if !prefix.isEmpty {
                line.append(NSAttributedString(string: prefix, attributes: [
                    .font: baseFont, .foregroundColor: label, .paragraphStyle: para
                ]))
            }
            // Split on backticks: even indices = normal, odd = code
            let backtickParts = text.components(separatedBy: "`")
            for (i, part) in backtickParts.enumerated() {
                if i % 2 == 1 {
                    line.append(NSAttributedString(string: part, attributes: [
                        .font: monoFont, .foregroundColor: label,
                        .backgroundColor: codeBg, .paragraphStyle: para
                    ]))
                } else {
                    // Within normal text, split on ** for bold
                    let boldParts = part.components(separatedBy: "**")
                    for (j, boldPart) in boldParts.enumerated() {
                        let font = j % 2 == 1 ? NSFont.boldSystemFont(ofSize: baseFont.pointSize) : baseFont
                        line.append(NSAttributedString(string: boldPart, attributes: [
                            .font: font, .foregroundColor: label, .paragraphStyle: para
                        ]))
                    }
                }
            }
            line.append(NSAttributedString(string: "\n"))
            out.append(line)
        }

        for line in markdown.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") || t.hasPrefix("# ") {
                let text = t.hasPrefix("## ") ? String(t.dropFirst(3)) : String(t.dropFirst(2))
                plain(text, font: h2Font, para: headingPara)
            } else if t.hasPrefix("### ") {
                plain(String(t.dropFirst(4)), font: h3Font, para: headingPara)
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                inline(String(t.dropFirst(2)), baseFont: bodyFont, para: listPara, prefix: "• ")
            } else if !t.isEmpty {
                inline(t, baseFont: bodyFont, para: normalPara)
            }
        }

        return out
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}