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
        config.onStateChange = { [weak statusItemController, weak settings] in
            statusItemController?.refresh()
            // 设置窗口里改了「界面语言」也走这条路：窗口标题与 AppKit 分段控件不会自己重绘。
            settings?.applyLanguageChange()
        }
        // 菜单是个静态 NSMenu，没人刷新它就永远保持构建时的文案。少了这一句，引擎在启动后
        // 自己跑起来了，菜单栏还一直写着「等待辅助功能授权」——而这恰恰是用户最需要看准的一行。
        engine.onStateChange = { [weak statusItemController] in
            statusItemController?.refresh()
        }
        config.start()
        // 先把规则集交给引擎，再启动应用目录。目录启动时会立刻刷新一次并回调一次；如果那时引擎
        // 拿到的还是空配置，就会先白白构建一份「0 条手势」的索引（启动日志里会看到两次构建，
        // 调试面板的 `idx rebuilds` 也会从 2 起跳）。顺序反过来正好只构建一次。
        engine.apply(config: config.config, targetMode: config.preferences.targetMode)
        appDirectory.start()
        engine.apply(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        engine.apply(overlayStyle: OverlayStyle(preferences: config.preferences))

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
        engine.startIfPermitted()
        switch engine.grantState {
        case .granted:
            break
        case .notGrantedYet:
            // Show the system prompt offering to open the Accessibility pane. The engine starts by
            // itself as soon as the checkbox is ticked (see EngineController).
            PermissionGate.requestAccessibility()
        case .lostAfterUpdate:
            // The system prompt would not explain *why*. An update re-issued the app's identity and
            // dropped the grant, which looks like a broken release, so it gets its own explanation
            // (at most once per launch).
            engine.presentGrantLostAlertIfNeeded()
        }

        // A menu-bar-only app (LSUIElement) otherwise shows nothing but a small icon on a fresh
        // install, which reads as "it did not work". Open the settings window, and report what the
        // first run actually did so the result is not buried in the log.
        if !hadConfig {
            settings.show()
            switch config.status {
            case .imported, .seeded:
                config.presentImportSummary()
            default:
                break
            }
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
