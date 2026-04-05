import AppKit
import Combine
import SwiftyBeaver
import SwiftUI

@main
struct IntelliWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible window — UI is driven by NSStatusItem and the floating panel.
        Settings { EmptyView() }
    }
}

/// Bootstraps all subsystems, wires them to the orchestrator, and runs
/// the prerequisite initializer before the app becomes fully operational.
///
/// On first launch, shows the FirstRunView onboarding wizard instead of
/// the headless AppInitializer.
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var settings: SettingsService!
    private var orchestrator: PipelineOrchestrator!
    private var hotkeyManager: HotkeyManager!
    private var initializer: AppInitializer!
    private var menuBarController: MenuBarController!
    private var floatingPanelController: FloatingPanelController!
    private var healthCheckTimer: Timer?

    // First-run
    private var firstRunWindow: NSWindow?
    private var firstRunCoordinator: FirstRunCoordinator?
    private var firstRunCancellable: AnyCancellable?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupLogging()
        log.info("App launching")

        // 0. Centralized settings
        settings = SettingsService()

        // 1. Create subsystems (sync, instant)
        let recorder = WhisperKitRecorder()
        let transcriber = WhisperKitTranscriber()
        let contextDetector = ContextDetector()
        let formatter = OllamaFormatter()
        let clipboard = ClipboardManager()

        orchestrator = PipelineOrchestrator(
            settings: settings,
            recorder: recorder,
            transcriber: transcriber,
            contextDetector: contextDetector,
            formatter: formatter,
            clipboard: clipboard
        )

        // Restore persisted preferences into the orchestrator.
        orchestrator.preferredLanguage = Language(rawValue: settings.preferredLanguage)
        orchestrator.outputMode = OutputMode(rawValue: settings.outputMode) ?? .clipboard
        log.info("Preferences restored: lang=\(orchestrator.preferredLanguage?.rawValue ?? "auto"), output=\(orchestrator.outputMode.rawValue)")

        // 2. Create hotkey manager (start() is deferred to initializer or first-run)
        hotkeyManager = HotkeyManager()

        // 3. Create UI controllers
        menuBarController = MenuBarController(orchestrator: orchestrator)
        floatingPanelController = FloatingPanelController(orchestrator: orchestrator, settings: settings)

        // 4. First-run or normal initialization
        if !settings.setupCompleted {
            log.info("First launch — showing setup wizard")
            let coordinator = FirstRunCoordinator(
                settings: settings,
                transcriber: transcriber,
                formatter: formatter,
                hotkey: hotkeyManager,
                orchestrator: orchestrator
            )
            firstRunCoordinator = coordinator

            // Observe completion → close window, start normal operation
            firstRunCancellable = coordinator.$isComplete
                .filter { $0 }
                .first()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.firstRunCompleted()
                }

            showFirstRunWindow(coordinator: coordinator)
        } else {
            // Subsequent launch: wire hotkey and run headless checks
            log.info("Subsequent launch — running headless initialization")
            orchestrator.wire(hotkey: hotkeyManager)
            initializer = AppInitializer()
            Task {
                await initializer.run(
                    settings: settings,
                    hotkey: hotkeyManager,
                    transcriber: transcriber,
                    formatter: formatter,
                    orchestrator: orchestrator
                )
            }
            startHealthCheckTimer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("App terminating")
        healthCheckTimer?.invalidate()
    }

    // MARK: - First-run window

    @MainActor
    private func showFirstRunWindow(coordinator: FirstRunCoordinator) {
        let firstRunView = FirstRunView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: firstRunView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "IntelliWhisper Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Re-activate after a delay to steal focus back from the pkg installer
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }

        firstRunWindow = window
    }

    @MainActor
    private func firstRunCompleted() {
        log.info("First-run wizard completed — relaunching app for permissions to take effect")
        firstRunWindow?.close()

        // Relaunch via 'open' after a brief delay so the current process can terminate cleanly
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [bundlePath]
            try? task.run()
        }

        NSApp.terminate(nil)
    }

    // MARK: - Health check

    @MainActor
    private func startHealthCheckTimer() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.orchestrator.checkOllamaHealth()
            }
        }
    }
}
