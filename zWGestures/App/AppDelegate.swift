import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var engine: EngineController?
    private var debugHUD: DebugHUDWindow?
    private var settings: SettingsWindowController?
    private var config: ConfigController?
    private var appDirectory: AppDirectory?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("""
            zWGestures \(Bundle.main.shortVersion, privacy: .public) launched \
            (pid \(ProcessInfo.processInfo.processIdentifier, privacy: .public), \
            arch \(BuildInfo.architecture, privacy: .public), \
            translated \(BuildInfo.isTranslated, privacy: .public))
            """)

        let config = ConfigController()
        let appDirectory = AppDirectory()
        let engine = EngineController(
            appDirectory: appDirectory,
            startDragTimeout: config.preferences.startDragTimeoutSeconds
        )
        let debugHUD = DebugHUDWindow(coordinator: engine.coordinator)
        let settings = SettingsWindowController(
            coordinator: SettingsCoordinator(config: config, engine: engine)
        )
        let statusItemController = StatusItemController(
            engine: engine,
            config: config,
            debugHUD: debugHUD,
            settings: settings,
            loginItem: LoginItem()
        )

        self.config = config
        self.appDirectory = appDirectory
        self.engine = engine
        self.debugHUD = debugHUD
        self.settings = settings
        self.statusItemController = statusItemController

        let hadConfig = config.store.hasConfig
        config.onStateChange = { [weak statusItemController] in
            statusItemController?.refresh()
        }
        config.start()
        appDirectory.start()
        engine.apply(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        engine.apply(overlayStyle: OverlayStyle(preferences: config.preferences))
        engine.apply(config: config.config, targetMode: config.preferences.targetMode)

        if ProcessInfo.processInfo.environment["ZWG_DEBUG_HUD"] == "1" {
            debugHUD.show()
        }
        if ProcessInfo.processInfo.environment["ZWG_SETTINGS_PANEL"] == "1" {
            settings.show()
        }

        PermissionGate.logCurrentState()
        // The login item lives in the system, not in our config file: record what the system
        // says at launch, so a failure is diagnosable from the log alone.
        Log.app.notice("""
            登录项状态：\(String(describing: LoginItem().status), privacy: .public)，\
            应用路径：\(Bundle.main.bundlePath, privacy: .public)
            """)
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
