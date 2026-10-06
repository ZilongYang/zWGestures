import Foundation

/// Facts about the running build. Used by the About panel and by the P0
/// acceptance check that the app runs natively on Apple Silicon.
public enum BuildInfo {
    /// `"arm64"` on Apple Silicon, `"x86_64"` under Rosetta or on Intel.
    public static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    /// False when the process is running under Rosetta translation.
    public static var isAppleSiliconNative: Bool { architecture == "arm64" }

    /// True when the current process is being translated by Rosetta.
    public static var isTranslated: Bool {
        guard let value = try? sysctlInt("sysctl.proc_translated") else { return false }
        return value == 1
    }

    /// When the running executable was written — that is, which build this process is.
    ///
    /// Worth showing in the UI because `open` on an already-running app only brings the old
    /// process forward: without a visible stamp there is no way to tell "my change didn't work"
    /// from "I am still looking at yesterday's binary".
    public static var buildDate: Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    /// Short, sortable rendering of `buildDate`, e.g. `09-28 15:10:40`.
    public static var buildStamp: String {
        guard let date = buildDate else { return L10n.text(.buildUnknown) }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func sysctlInt(_ name: String) throws -> Int32 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        return value
    }
}
