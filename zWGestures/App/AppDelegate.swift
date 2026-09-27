import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var engine: EngineController?
    private var debugHUD: DebugHUDWindow?
    private var config: ConfigController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("""
            zWGestures \(Bundle.main.shortVersion, privacy: .public) launched \
            (pid \(ProcessInfo.processInfo.processIdentifier, privacy: .public), \
            arch \(BuildInfo.architecture, privacy: .public), \
            translated \(BuildInfo.isTranslated, privacy: .public))
            """)

        let config = ConfigController()
        let engine = EngineController(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        let debugHUD = DebugHUDWindow(coordinator: engine.coordinator)
        let statusItemController = StatusItemController(
            engine: engine,
            config: config,
            debugHUD: debugHUD
        )

        self.config = config
        self.engine = engine
        self.debugHUD = debugHUD
        self.statusItemController = statusItemController

        let hadConfig = config.store.hasConfig
        config.onStateChange = { [weak statusItemController] in
            statusItemController?.refresh()
        }
        config.start()
        engine.apply(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        engine.applyRecognition(config: config.config)

        if ProcessInfo.processInfo.environment["ZWG_DEBUG_HUD"] == "1" {
            debugHUD.show()
        }

        PermissionGate.logCurrentState()
        if !PermissionGate.isAccessibilityTrusted {
            // Show the system prompt offering to open the Accessibility pane. The engine
            // starts by itself as soon as the checkbox is ticked (see EngineController).
            PermissionGate.requestAccessibility()
        }
        engine.startIfPermitted()

        // Report a first-time migration so the user can see exactly what came across.
        if !hadConfig, case .imported = config.status {
            config.presentImportSummary()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("zWGestures terminating")
        // Always release the event tap before exiting, so nothing stays swallowed.
        engine?.stop()
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    var buildVersion: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}
