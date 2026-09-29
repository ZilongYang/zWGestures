import AppKit

/// The menu-bar item.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let configItem = NSMenuItem()
    private let engineItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private let importItem = NSMenuItem()
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
        // 打开菜单时再刷新一次，作为 `onStateChange` 之外的兜底：引擎会因为权限轮询自己启动、
        // 也会被急停快捷键暂停，而一个把状态写错的菜单栏比没有菜单栏更糟。
        menu.delegate = self
    }

    /// 每次打开菜单都按实时状态重建文案。
    ///
    /// 静态 `NSMenu` 不会自己更新，不刷新就永远显示构建那一刻的文案。这个 bug 真实发生过：
    /// 启动时菜单写「等待辅助功能授权」，而引擎其实已经跑起来了。
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureMenu() {
        configItem.isEnabled = false
        engineItem.isEnabled = false

        pauseItem.target = self
        pauseItem.action = #selector(handlePauseResume)

        importItem.title = "从 WGestures 导入配置…"
        importItem.target = self
        importItem.action = #selector(handleImport)

        settingsItem.title = "打开设置…"
        settingsItem.target = self
        settingsItem.action = #selector(handleOpenSettings)
        settingsItem.keyEquivalent = ","

        quickStartItem.title = "打开快速入门"
        quickStartItem.isEnabled = false

        debugHUDItem.title = "显示调试面板"
        debugHUDItem.target = self
        debugHUDItem.action = #selector(handleToggleDebugHUD)

        loginItemToggle.target = self
        loginItemToggle.action = #selector(handleToggleLoginItem)

        permissionItem.target = self
        permissionItem.action = #selector(handlePermissionItem)

        aboutItem.title = "关于 zWGestures"
        aboutItem.target = self
        aboutItem.action = #selector(handleAbout)

        quitItem.title = "退出 zWGestures"
        quitItem.target = self
        quitItem.action = #selector(handleQuit)
        quitItem.keyEquivalent = "q"

        menu.addItem(configItem)
        menu.addItem(engineItem)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(importItem)
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

    func refresh() {
        configItem.title = config.status.localizedText

        if engine.isRunning {
            engineItem.title = "手势引擎：运行中"
            pauseItem.title = "暂停手势引擎"
            pauseItem.isEnabled = true
        } else if !engine.isPermitted {
            engineItem.title = switch engine.grantState {
            case .lostAfterUpdate: "手势引擎：授权已失效（需重新授权）"
            default: "手势引擎：等待辅助功能授权"
            }
            pauseItem.title = "手势引擎未运行"
            pauseItem.isEnabled = false
        } else {
            engineItem.title = "手势引擎：\(engine.lastFailureReason ?? "已暂停")"
            pauseItem.title = "继续手势引擎"
            pauseItem.isEnabled = true
        }

        debugHUDItem.state = debugHUD.isVisible ? .on : .off

        // Read the system, not `prefs.json`: the switch can be revoked in System Settings, and the
        // mechanism matters — the LaunchAgent fallback does not appear in System Settings.
        let loginStatus = loginItem.status
        loginItemToggle.title = loginStatus.isOn
            ? "开机自动启动：已开启（\(loginItem.mechanism.localizedName)）"
            : loginStatus.localizedText
        loginItemToggle.state = loginStatus.isOn ? .on : .off
        loginItemToggle.toolTip = Bundle.main.bundlePath

        permissionItem.title = switch engine.grantState {
        case .granted: "辅助功能权限：已授权"
        case .lostAfterUpdate: "辅助功能权限：已失效（点击重新授权）"
        case .notGrantedYet: "辅助功能权限：未授权（点击前往授权）"
        }
    }

    @objc private func handlePauseResume() {
        engine.isRunning ? engine.pause(reason: "用户从菜单暂停") : engine.resume()
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
            alert.messageText = wantEnabled ? "无法开启开机自启" : "无法关闭开机自启"
            alert.alertStyle = .warning
            alert.informativeText = """
                \(failure)

                当前应用路径：
                \(Bundle.main.bundlePath)

                登录项记录的是应用路径，请把 zWGestures.app 放到一个固定的位置\
                （例如 /Applications），再重试。
                """
            alert.addButton(withTitle: "好")
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
                string: "原生的 Apple Silicon 鼠标手势工具\n"
                    + "运行架构：\(BuildInfo.architecture)\n"
                    + "急停快捷键：\(PanicShortcut.displayName)\n"
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
