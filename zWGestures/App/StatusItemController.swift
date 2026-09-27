import AppKit

/// The menu-bar item.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let configItem = NSMenuItem()
    private let engineItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private let importItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let quickStartItem = NSMenuItem()
    private let debugHUDItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let aboutItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    private let engine: EngineController
    private let config: ConfigController
    private let debugHUD: DebugHUDWindow

    init(engine: EngineController, config: ConfigController, debugHUD: DebugHUDWindow) {
        self.engine = engine
        self.config = config
        self.debugHUD = debugHUD
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
        settingsItem.isEnabled = false

        quickStartItem.title = "打开快速入门"
        quickStartItem.isEnabled = false

        debugHUDItem.title = "显示调试面板"
        debugHUDItem.target = self
        debugHUDItem.action = #selector(handleToggleDebugHUD)

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
            engineItem.title = "手势引擎：等待辅助功能授权"
            pauseItem.title = "手势引擎未运行"
            pauseItem.isEnabled = false
        } else {
            engineItem.title = "手势引擎：\(engine.lastFailureReason ?? "已暂停")"
            pauseItem.title = "继续手势引擎"
            pauseItem.isEnabled = true
        }

        debugHUDItem.state = debugHUD.isVisible ? .on : .off
        permissionItem.title = engine.isPermitted
            ? "辅助功能权限：已授权"
            : "辅助功能权限：未授权（点击前往授权）"
    }

    @objc private func handlePauseResume() {
        engine.isRunning ? engine.pause(reason: "用户从菜单暂停") : engine.resume()
        refresh()
    }

    @objc private func handleImport() {
        NSApp.activate(ignoringOtherApps: true)
        config.importLegacy()
        engine.apply(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        refresh()
        config.presentImportSummary()
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
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "zWGestures",
            .applicationVersion: "\(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))",
            .credits: NSAttributedString(
                string: "原生的 Apple Silicon 鼠标手势工具\n"
                    + "运行架构：\(BuildInfo.architecture)\n"
                    + "急停快捷键：\(PanicShortcut.displayName)\n"
                    + config.status.localizedText,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
            ),
        ])
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
