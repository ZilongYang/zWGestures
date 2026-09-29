import Foundation

/// Where a launch should get its configuration from.
///
/// Split out of `ConfigController` because the ordering is the whole point and it is easy to get
/// wrong. An existing configuration always wins — the user may have edited it, and re-importing
/// over it would silently discard their work. After that the original app's installation wins,
/// because that is what the user is actually using today. Only when there is neither do we seed the
/// pack built into the app, which is the case a fresh download lands in.
public enum ConfigSeedSource: Equatable, Sendable {
    /// A configuration already exists: load it and change nothing.
    case existingConfig
    /// Import from the original WGestures installation at this directory.
    case legacyInstall(URL)
    /// Seed from the factory-default pack at this directory, which ships inside the app bundle.
    case factoryDefault(URL)
}

public enum ConfigBootstrapper {
    /// Decides what a launch should do.
    ///
    /// - Returns: `nil` only when there is no configuration and neither source is available. The app
    ///   then runs with an empty gesture set, which the status line reports.
    public static func decide(
        hasConfig: Bool,
        legacyDirectory: URL?,
        defaultsDirectory: URL?
    ) -> ConfigSeedSource? {
        if hasConfig { return .existingConfig }
        if let legacyDirectory { return .legacyInstall(legacyDirectory) }
        if let defaultsDirectory { return .factoryDefault(defaultsDirectory) }
        return nil
    }
}
