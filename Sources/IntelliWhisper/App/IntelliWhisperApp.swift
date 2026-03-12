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

        // 1. Create subsystems (sync, instant)
        let recorder = WhisperKitRecorder()
        let transcriber = WhisperKitTranscriber()
        let contextDetector = ContextDetector()
        let formatter = OllamaFormatter()
        let clipboard = ClipboardManager()

        orchestrator = PipelineOrchestrator(
            recorder: recorder,
            transcriber: transcriber,
            contextDetector: contextDetector,
            formatter: formatter,
            clipboard: clipboard
        )

        // Restore persisted preferences into the orchestrator.
        if let langRaw = UserDefaults.standard.string(forKey: "preferredLanguage") {
            orchestrator.preferredLanguage = Language(rawValue: langRaw) // nil for "auto"
        }
        if let modeRaw = UserDefaults.standard.string(forKey: "outputMode"),
           let mode = OutputMode(rawValue: modeRaw) {
            orchestrator.outputMode = mode
        }
        log.info("Preferences restored: lang=\(orchestrator.preferredLanguage?.rawValue ?? "auto"), output=\(orchestrator.outputMode.rawValue)")

        // 2. Create hotkey manager (start() is deferred to initializer or first-run)
        hotkeyManager = HotkeyManager()

        // 3. Create UI controllers
        menuBarController = MenuBarController(orchestrator: orchestrator)
        floatingPanelController = FloatingPanelController(orchestrator: orchestrator)

        // 4. First-run or normal initialization
        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            log.info("First launch — showing setup wizard")
            let coordinator = FirstRunCoordinator(
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

        firstRunWindow = window
    }

    @MainActor
    private func firstRunCompleted() {
        log.info("First-run wizard completed")
        firstRunWindow?.close()
        firstRunWindow = nil
        firstRunCoordinator = nil
        firstRunCancellable = nil

        // Ensure hotkey is wired and started — the wizard may have
        // failed or skipped Input Monitoring, so retry here.
        orchestrator.wire(hotkey: hotkeyManager)
        if hotkeyManager.eventTap == nil {
            _ = hotkeyManager.start()
        }

        startHealthCheckTimer()
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
