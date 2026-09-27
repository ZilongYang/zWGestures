import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var engine: EngineController?
    private var debugHUD: DebugHUDWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("""
            zWGestures \(Bundle.main.shortVersion, privacy: .public) launched \
            (pid \(ProcessInfo.processInfo.processIdentifier, privacy: .public), \
            arch \(BuildInfo.architecture, privacy: .public), \
            translated \(BuildInfo.isTranslated, privacy: .public))
            """)

        let engine = EngineController()
        let debugHUD = DebugHUDWindow(coordinator: engine.coordinator)
        let statusItemController = StatusItemController(engine: engine, debugHUD: debugHUD)

        engine.onStateChange = { [weak statusItemController] in
            statusItemController?.refresh()
        }

        self.engine = engine
        self.debugHUD = debugHUD
        self.statusItemController = statusItemController

        if ProcessInfo.processInfo.environment["ZWG_DEBUG_HUD"] == "1" {
            debugHUD.show()
        }

        PermissionGate.logCurrentState()
        engine.startIfPermitted()
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
