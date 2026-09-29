import Foundation

/// The user-level launch agent used as a fallback when `SMAppService` will not register the app.
///
/// `SMAppService.mainApp` goes through BackgroundTaskManagement, which is strict about the app's
/// signature identity. This build is signed with a **local self-signed certificate and no team
/// identifier** (`TeamIdentifier=not set`), and on this machine it reports `.notFound` even when the
/// app sits in `/Applications` and is registered with LaunchServices — the system never records a
/// login item at all (`sfltool dumpbtm` stays empty). A launch agent in `~/Library/LaunchAgents` is
/// the plain user-level mechanism that does not depend on any of that.
///
/// The plist launches the app through `/usr/bin/open -a` rather than executing the binary: that
/// keeps the launch going through LaunchServices (so an already-running copy is merely activated
/// instead of starting a second instance), which matters for a menu-bar app that the user may well
/// have started by hand.
public enum LaunchAgent {
    public static let label = "io.github.zilongyang.zwgestures"

    /// `~/Library/LaunchAgents/io.github.zilongyang.zwgestures.plist`.
    public static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    /// The plist contents for an app at `appPath`.
    ///
    /// Built with `PropertyListSerialization` rather than by hand so a malformed file — which would
    /// make autostart fail silently — cannot be produced. Throws instead of returning empty data,
    /// so the caller can report the failure to the user.
    public static func makePlist(appPath: String) throws -> Data {
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
            // A menu-bar app: let it come up without being treated as a background daemon.
            "ProcessType": "Interactive",
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: contents,
            format: .xml,
            options: 0
        )
    }
}
