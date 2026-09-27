import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("""
            zWGestures \(Bundle.main.shortVersion, privacy: .public) launched \
            (pid \(ProcessInfo.processInfo.processIdentifier, privacy: .public), \
            arch \(BuildInfo.architecture, privacy: .public), \
            translated \(BuildInfo.isTranslated, privacy: .public))
            """)

        statusItemController = StatusItemController()

        PermissionGate.logCurrentState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("zWGestures terminating")
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
