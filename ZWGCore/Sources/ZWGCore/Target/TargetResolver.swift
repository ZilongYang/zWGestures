import Foundation

/// Who the gesture was aimed at.
public struct WGApplicationIdentity: Sendable, Equatable {
    public var pid: Int32
    public var bundleIdentifier: String?
    public var executablePath: String?
    public var localizedName: String?

    public init(
        pid: Int32,
        bundleIdentifier: String? = nil,
        executablePath: String? = nil,
        localizedName: String? = nil
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.localizedName = localizedName
    }
}

public struct WGResolvedTarget: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Nothing more specific matched.
        case general
        /// An application-specific target.
        case application
        /// The desktop's own special target.
        case desktop
    }

    public var target: WGTarget
    public var kind: Kind
    /// The application the gesture was aimed at, when one was resolved.
    public var application: WGApplicationIdentity?
    /// Which trigger inputs this target permits.
    public var triggerMatrix: WGTriggerMatrix

    public var displayName: String {
        switch kind {
        case .general: "全局"
        case .desktop: target.name
        case .application: application?.localizedName ?? target.name
        }
    }
}

/// Picks which gesture set applies to a gesture.
///
/// The lookup order mirrors the original app: a special target for the desktop wins, then an
/// application target, then the general fallback. Groups are not implemented yet — no
/// configuration encountered so far uses them, and their on-disk shape is unknown.
public enum TargetResolver {
    public static func resolve(
        config: WGConfig,
        application: WGApplicationIdentity?,
        isOverDesktop: Bool = false,
        mode: WGTargetMode = .focused
    ) -> WGResolvedTarget {
        let chosen: WGTarget
        let kind: WGResolvedTarget.Kind

        if isOverDesktop, let desktop = config.specials.first(where: { $0.kind == .desktop }) {
            chosen = desktop
            kind = .desktop
        } else if let application, let match = matchApplication(application, in: config.apps) {
            chosen = match
            kind = .application
        } else {
            chosen = config.general
            kind = .general
        }

        return WGResolvedTarget(
            target: chosen,
            kind: kind,
            application: application,
            triggerMatrix: WGTriggerMatrix.effective(for: chosen, inheriting: config.general)
        )
    }

    /// Finds the application target for `application`.
    ///
    /// Existing configurations can identify a target either by bundle identifier or, when the
    /// bundle identifier is absent, by the executable path (the reference configuration's
    /// Finder target only has a path). Both forms are compared, and `.app` bundles are also
    /// compared as bundles so a path recorded on another machine still matches.
    static func matchApplication(_ application: WGApplicationIdentity, in targets: [WGTarget]) -> WGTarget? {
        let candidates = targets.filter { $0.kind == .app }

        // Bundle identifiers are authoritative, so they are matched in a pass of their own:
        // otherwise an earlier path-only target could shadow a later, more precise one.
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            for target in candidates where target.bundleId == bundleIdentifier {
                return target
            }
        }

        guard let executablePath = application.executablePath else { return nil }
        let applicationBundlePath = bundlePath(of: executablePath)

        for target in candidates {
            guard target.bundleId == nil || target.bundleId!.isEmpty,
                  let targetPath = target.path, !targetPath.isEmpty
            else { continue }

            if targetPath == executablePath || bundlePath(of: targetPath) == applicationBundlePath {
                return target
            }
        }
        return nil
    }

    /// `/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder` -> `…/Finder.app`.
    ///
    /// Returns the input unchanged when it does not point inside an application bundle.
    public static func bundlePath(of path: String) -> String {
        guard let range = path.range(of: ".app/", options: .backwards) else { return path }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }
}

extension WGApplicationIdentity {
    /// The preferred human-readable name, falling back to the bundle identifier.
    public var displayName: String {
        localizedName ?? bundleIdentifier ?? executablePath.map { ($0 as NSString).lastPathComponent } ?? "未知应用"
    }
}
