import AppKit

/// The menu-bar item. In P0 it only reports state; pause/resume, settings and
/// quick start get wired up in later phases.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let engineItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let quickStartItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let aboutItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    override init() {
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
        engineItem.isEnabled = false
        settingsItem.title = "打开设置…"
        settingsItem.isEnabled = false
        quickStartItem.title = "打开快速入门"
        quickStartItem.isEnabled = false
        permissionItem.target = self
        permissionItem.action = #selector(handlePermissionItem)
        aboutItem.title = "关于 zWGestures"
        aboutItem.target = self
        aboutItem.action = #selector(handleAbout)
        quitItem.title = "退出 zWGestures"
        quitItem.target = self
        quitItem.action = #selector(handleQuit)
        quitItem.keyEquivalent = "q"

        menu.addItem(engineItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(quickStartItem)
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(aboutItem)
        menu.addItem(quitItem)
    }

    func refresh() {
        engineItem.title = "手势引擎未启动（P1）"
        permissionItem.title = PermissionGate.isAccessibilityTrusted
            ? "辅助功能权限：已授权"
            : "辅助功能权限：未授权（点击前往授权）"
    }

    @objc private func handlePermissionItem() {
        if PermissionGate.isAccessibilityTrusted {
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
                    + "运行架构：\(BuildInfo.architecture)",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
            ),
        ])
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
