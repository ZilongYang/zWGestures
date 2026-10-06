import AppKit

/// The menu-bar item.
///
/// 🔴 **不要让它实现 `NSMenuDelegate`（或任何 AppKit 会从非事件路径回调的协议）。**
/// 2026-10-06 的崩溃 `zWGestures-2026-10-06-024535.ips` 就是这么来的：本类带 `@MainActor`，
/// 于是 `menuWillOpen(_:)` 这个 `NSMenuDelegate` 实现会**继承隔离并在入口插入「我在主 actor 上吗」
/// 的运行时检查**；AppKit 从状态栏菜单的场景路径（`FrontBoardServices scene:handlePrivateActions:`
/// → `NSSceneStatusItem _beginExpandedInterfaceSession`）调用它时，那个检查自己 fault 了
/// （SIGBUS in `SerialExecutorRef::isMainExecutor`）—— 与 09-28 那两次（Timer block、
/// `TrailView.isFlipped`）是同一族。
///
/// 所以菜单文案靠**推送式刷新**：`onStateChange` 回调 + 每次菜单动作后 + 应用被激活时。
/// 唯一会短暂过期的情形：在「系统设置」里改开机自启、且期间本应用从未被激活 —— 点一下那条
/// 菜单项就会刷新。宁可这样，也不要一个会偶发崩溃的回调入口。
/// `scripts/check-appkit-isolation.py` 已把这类协议回调列入守卫（原先只查 `override`，是盲区）。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let configItem = NSMenuItem()
    private let engineItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private let importItem = NSMenuItem()
    private let renameNamesItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let quickStartItem = NSMenuItem()
    private let debugHUDItem = NSMenuItem()
    private let loginItemToggle = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let aboutItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    private let engine: EngineController
    private let config: ConfigController
    private let debugHUD: DebugHUDWindow
    private let settings: SettingsWindowController
    private let loginItem: LoginItem

    init(
        engine: EngineController,
        config: ConfigController,
        debugHUD: DebugHUDWindow,
        settings: SettingsWindowController,
        loginItem: LoginItem
    ) {
        self.engine = engine
        self.config = config
        self.debugHUD = debugHUD
        self.settings = settings
        self.loginItem = loginItem
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configureMenu()
        observeActivation()
        refresh()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "zWGestures")
        image?.isTemplate = true
        button.image = image
        button.image?.size = NSSize(width: 18, height: 18)
        button.toolTip = "zWGestures"
        if image == nil {
            button.title = "zW"
        }
        statusItem.menu = menu
    }

    /// 应用被激活时再刷新一次，作为 `onStateChange` 之外的兜底。
    ///
    /// 注意这里**不能**用 `NSMenuDelegate.menuWillOpen` 做兜底 —— 那正是 2026-10-06 崩溃的入口
    /// （见类注释）。`NotificationCenter` 的闭包不是主 actor 隔离的，所以用 `Task` 正常跳回主 actor，
    /// 而不是让编译器插入 `assumeIsolated`：后者是 09-28 那次 SIGBUS 的成因。
    ///
    /// 不保存 token、也不注销：本对象与 App 同生命周期，而 token 是非 Sendable 的，
    /// 存下来只会让 `deinit`（在 Swift 6 里是非隔离的）无法访问它。
    private func observeActivation() {
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func configureMenu() {
        configItem.isEnabled = false
        engineItem.isEnabled = false

        pauseItem.target = self
        pauseItem.action = #selector(handlePauseResume)

        importItem.target = self
        importItem.action = #selector(handleImport)

        renameNamesItem.target = self
        renameNamesItem.action = #selector(handleRenameEnglishNames)

        settingsItem.target = self
        settingsItem.action = #selector(handleOpenSettings)
        settingsItem.keyEquivalent = ","

        quickStartItem.isEnabled = false

        debugHUDItem.target = self
        debugHUDItem.action = #selector(handleToggleDebugHUD)

        loginItemToggle.target = self
        loginItemToggle.action = #selector(handleToggleLoginItem)

        permissionItem.target = self
        permissionItem.action = #selector(handlePermissionItem)

        aboutItem.target = self
        aboutItem.action = #selector(handleAbout)

        quitItem.target = self
        quitItem.action = #selector(handleQuit)
        quitItem.keyEquivalent = "q"

        menu.addItem(configItem)
        menu.addItem(engineItem)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(importItem)
        menu.addItem(renameNamesItem)
        menu.addItem(settingsItem)
        menu.addItem(quickStartItem)
        menu.addItem(debugHUDItem)
        menu.addItem(.separator())
        menu.addItem(loginItemToggle)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(aboutItem)
        menu.addItem(quitItem)
    }

    /// 菜单里那些「静态」标题。
    ///
    /// 必须每次刷新都重设：语言可以在设置界面里改，而 `configureMenu()` 只在初始化时跑一次 ——
    /// 写在那边就会出现「切了语言但菜单还是旧语言」。
    private func applyLocalizedTitles() {
        importItem.title = L10n.text(.menuImportFromWGestures)
        renameNamesItem.title = L10n.text(.menuRenameEnglishNames)
        settingsItem.title = L10n.text(.menuOpenSettings)
        quickStartItem.title = L10n.text(.menuOpenQuickStart)
        debugHUDItem.title = L10n.text(.menuShowDebugHUD)
        aboutItem.title = L10n.text(.menuAbout)
        quitItem.title = L10n.text(.menuQuit)
    }

    func refresh() {
        applyLocalizedTitles()
        configItem.title = config.status.localizedText

        if engine.isRunning {
            engineItem.title = L10n.text(.menuEngineRunning)
            pauseItem.title = L10n.text(.menuEnginePause)
            pauseItem.isEnabled = true
        } else if !engine.isPermitted {
            engineItem.title = switch engine.grantState {
            case .lostAfterUpdate: L10n.text(.menuEnginePermissionLost)
            default: L10n.text(.menuEngineWaitingPermission)
            }
            pauseItem.title = L10n.text(.menuEngineNotRunning)
            pauseItem.isEnabled = false
        } else {
            engineItem.title = L10n.format(
                .menuEngineStatusFormat,
                engine.lastFailureReason ?? L10n.text(.menuEnginePausedByUser)
            )
            pauseItem.title = L10n.text(.menuEngineResume)
            pauseItem.isEnabled = true
        }

        debugHUDItem.state = debugHUD.isVisible ? .on : .off

        // Read the system, not `prefs.json`: the switch can be revoked in System Settings, and the
        // mechanism matters — the LaunchAgent fallback does not appear in System Settings.
        let loginStatus = loginItem.status
        loginItemToggle.title = loginStatus.isOn
            ? L10n.format(.menuLoginItemOnFormat, loginItem.mechanism.localizedName)
            : loginStatus.localizedText
        loginItemToggle.state = loginStatus.isOn ? .on : .off
        loginItemToggle.toolTip = Bundle.main.bundlePath

        permissionItem.title = switch engine.grantState {
        case .granted: L10n.text(.menuPermissionGranted)
        case .lostAfterUpdate: L10n.text(.menuPermissionLost)
        case .notGrantedYet: L10n.text(.menuPermissionMissing)
        }
    }

    @objc private func handlePauseResume() {
        engine.isRunning ? engine.pause(reason: L10n.text(.menuEnginePausedByUser)) : engine.resume()
        refresh()
    }

    /// 把已知的英文手势名改成中文（显式动作；`ConfigStore.saveConfig` 写盘前自动备份）。
    @objc private func handleRenameEnglishNames() {
        NSApp.activate(ignoringOtherApps: true)
        guard config.englishNameCandidates > 0 else {
            let alert = NSAlert()
            alert.messageText = L10n.text(.renameNamesNothingToDo)
            alert.informativeText = L10n.text(.renameNamesNothingToDoDetail)
            alert.addButton(withTitle: L10n.text(.menuOK))
            alert.runModal()
            return
        }

        let changed = config.renameEnglishNames()
        let alert = NSAlert()
        alert.messageText = L10n.format(.renameNamesDoneFormat, changed)
        alert.informativeText = L10n.text(.renameNamesDoneDetail)
            + "\n\n" + config.store.configURL.path
        alert.addButton(withTitle: L10n.text(.menuOK))
        alert.runModal()
        refresh()
    }

    /// 启动时的一次性询问：配置里若还是原版那套英文手势名，问一次要不要改成中文。
    ///
    /// 无论选改还是不改，都先把「问过」记进 `prefs.json` —— 每次开机都弹会变成骚扰。
    func offerEnglishNameRenameIfNeeded() {
        guard config.shouldOfferEnglishNameRename else { return }
        let candidates = config.englishNameCandidates
        Log.app.notice("发现有 \(candidates, privacy: .public) 条英文手势名，已询问是否改成中文")

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.format(.renameNamesOfferFormat, config.englishNameCandidates)
        alert.informativeText = L10n.text(.renameNamesOfferDetail)
            + "\n\n" + config.store.configURL.path
        alert.addButton(withTitle: L10n.text(.renameNamesOfferAccept))
        alert.addButton(withTitle: L10n.text(.renameNamesOfferDecline))
        let accepted = alert.runModal() == .alertFirstButtonReturn
        // 记在**用户回答之后**：如果这次启动被中途杀掉（或像开发时那样被替换掉），
        // 下次还会再问一遍，而不是白白吞掉这次询问。
        config.rememberEnglishNameOffer()
        if accepted {
            _ = config.renameEnglishNames()
        }
        refresh()
    }

    @objc private func handleImport() {
        NSApp.activate(ignoringOtherApps: true)
        config.importLegacy()
        engine.apply(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        engine.apply(overlayStyle: OverlayStyle(preferences: config.preferences))
        engine.apply(config: config.config, targetMode: config.preferences.targetMode)
        refresh()
        config.presentImportSummary()
    }

    @objc private func handleToggleLoginItem() {
        let wantEnabled = !loginItem.isEnabled
        let failure = loginItem.setEnabled(wantEnabled)
        // Only mirror a switch that the system actually accepted.
        if failure == nil {
            config.update(autoStart: wantEnabled)
        }
        refresh()

        if let failure {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = wantEnabled
                ? L10n.text(.menuCannotEnableLoginItem)
                : L10n.text(.menuCannotDisableLoginItem)
            alert.alertStyle = .warning
            alert.informativeText = "\(failure)\n\n"
                + L10n.format(.menuLoginItemFailureHelpFormat, Bundle.main.bundlePath)
            alert.addButton(withTitle: L10n.text(.menuOK))
            alert.runModal()
        } else if loginItem.status == .requiresApproval {
            // macOS 需要用户在「登录项」里手动放行，直接把面板打开。
            loginItem.openLoginItemsSettings()
        }
    }

    @objc private func handleOpenSettings() {
        settings.show()
        refresh()
    }

    @objc private func handleToggleDebugHUD() {
        debugHUD.toggle()
        refresh()
    }

    @objc private func handlePermissionItem() {
        if engine.isPermitted {
            PermissionGate.openAccessibilitySettings()
        } else {
            PermissionGate.requestAccessibility()
            PermissionGate.openAccessibilitySettings()
        }
        refresh()
    }

    @objc private func handleAbout() {
        NSApp.activate(ignoringOtherApps: true)
        // 显式给出图标：macOS 26 上实测「老的 CFBundleIconFile + 独立 .icns」这条路会让
        // 关于面板渲染成空白（Finder 走图标服务，两条路不同），而 NSWorkspace 这条正是
        // Finder 用的那条、已验证可用。图标资源本身仍由 asset catalog 提供（见 project.yml）。
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "zWGestures",
            .applicationVersion: "\(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))",
            .credits: NSAttributedString(
                string: L10n.text(.aboutTagline) + "\n"
                    + L10n.format(.aboutArchitectureFormat, BuildInfo.architecture) + "\n"
                    + L10n.format(.aboutPanicShortcutFormat, PanicShortcut.displayName) + "\n"
                    + config.status.localizedText,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
            ),
        ]
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 128, height: 128)
        options[.applicationIcon] = icon
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
