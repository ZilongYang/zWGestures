import Foundation

/// Counts collected while reading a legacy configuration, so an import can be checked at a
/// glance ("49 intents in General, 3 in Finder") instead of trusted.
public struct WGImportStatistics: Sendable, Equatable {
    public var targets = 0
    public var intents = 0
    public var triggerRows = 0
    public var stepsByType: [String: Int] = [:]
    public var commandsByType: [String: Int] = [:]

    public var summary: String {
        let steps = stepsByType.sorted { $0.key < $1.key }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: "、")
        let commands = commandsByType.sorted { $0.key < $1.key }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: "、")
        return """
            目标 \(targets)、手势 \(intents)、触发方式 \(triggerRows)
            步骤：\(steps)
            命令：\(commands)
            """
    }
}

public struct WGImportResult: Sendable {
    public var config: WGConfig
    public var preferences: WGPreferences?
    public var warnings: [String]
    public var statistics: WGImportStatistics
    public var sourceDirectory: URL
    public var sourceVersion: String?
}

public enum WGImportError: Error, LocalizedError {
    case directoryNotFound
    case gesturesFileMissing(URL)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            "没有找到 WGestures 的配置目录"
        case .gesturesFileMissing(let url):
            "配置目录里没有 gestures.json：\(url.path)"
        }
    }
}

/// Reads an existing WGestures installation's configuration.
///
/// The legacy directory is only ever read, never written: the imported configuration is
/// stored under zWGestures' own application-support directory.
public enum LegacyConfigImporter {
    /// `~/Library/Application Support/com.yingdev.wgestures`
    public static var defaultRoot: URL {
        applicationSupportDirectory.appendingPathComponent("com.yingdev.wgestures", isDirectory: true)
    }

    /// The most likely version directory, e.g. `…/com.yingdev.wgestures/2.3.3`.
    public static func locateVersionDirectory(in root: URL? = nil) -> URL? {
        let root = root ?? defaultRoot
        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = entries.filter { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return false }
            return fileManager.fileExists(atPath: url.appendingPathComponent("gestures.json").path)
        }
        guard !candidates.isEmpty else { return nil }

        // Prefer whatever the original app last launched, then the highest version number.
        if let lastLaunched = try? String(
            contentsOf: root.appendingPathComponent("LastLaunchedVersion"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines),
            let match = candidates.first(where: { $0.lastPathComponent == lastLaunched })
        {
            return match
        }

        return candidates.max { compareVersions($0.lastPathComponent, $1.lastPathComponent) < 0 }
    }

    public static func load(from directory: URL) throws -> WGImportResult {
        let fileManager = FileManager.default
        let gesturesURL = directory.appendingPathComponent("gestures.json")
        guard fileManager.fileExists(atPath: gesturesURL.path) else {
            throw WGImportError.gesturesFileMissing(directory)
        }

        let decoded = try WGConfigCodec.decode(try Data(contentsOf: gesturesURL))

        var preferences: WGPreferences?
        var warnings = decoded.warnings
        let prefsURL = directory.appendingPathComponent("prefs.json")
        if fileManager.fileExists(atPath: prefsURL.path) {
            do {
                preferences = try WGConfigCodec.decodePreferences(try Data(contentsOf: prefsURL))
            } catch {
                warnings.append("prefs.json 解析失败，将使用默认偏好：\(error.localizedDescription)")
            }
        } else {
            warnings.append("配置目录里没有 prefs.json，将使用默认偏好")
        }

        return WGImportResult(
            config: decoded.config,
            preferences: preferences,
            warnings: warnings,
            statistics: statistics(for: decoded.config),
            sourceDirectory: directory,
            sourceVersion: directory.lastPathComponent
        )
    }

    public static func statistics(for config: WGConfig) -> WGImportStatistics {
        var statistics = WGImportStatistics()
        for target in config.allTargets {
            statistics.targets += 1
            statistics.intents += target.intents.count
            statistics.triggerRows += target.triggers.count

            for trigger in target.triggers {
                for step in trigger.def {
                    statistics.stepsByType[step.typeName, default: 0] += 1
                }
            }
            for intent in target.intents {
                for step in intent.gesture {
                    statistics.stepsByType[step.typeName, default: 0] += 1
                }
                statistics.commandsByType[intent.command.typeName, default: 0] += 1
            }
        }
        return statistics
    }

    /// Compares dotted version strings numerically, so 2.10 beats 2.9.
    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
