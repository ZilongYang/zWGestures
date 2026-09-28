import Foundation

/// zWGestures' own configuration storage.
///
/// Deliberately separate from the original app's directory: importing is a one-way read, so
/// the original configuration is never modified and can be re-imported at any time.
public final class ConfigStore: @unchecked Sendable {
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("zWGestures", isDirectory: true)
    }

    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL = ConfigStore.defaultDirectory) {
        self.directory = directory
    }

    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var preferencesURL: URL { directory.appendingPathComponent("prefs.json") }

    /// Previous copies of the files above, taken just before they are overwritten.
    ///
    /// The settings window edits the user's real configuration directly, so a bad save has to stay
    /// recoverable. Backups live in a subdirectory, which keeps them clear of `hasConfig` /
    /// `loadConfig` and of a legacy re-import.
    public var backupsDirectory: URL {
        directory.appendingPathComponent("Backups", isDirectory: true)
    }

    /// How many backups of each file to keep.
    public static let backupLimit = 10

    public var hasConfig: Bool {
        fileManager.fileExists(atPath: configURL.path)
    }

    // MARK: - Config

    public func loadConfig() throws -> WGConfigLoadResult {
        guard hasConfig else {
            return WGConfigLoadResult(config: WGConfig(), warnings: ["尚未导入配置，当前使用空的默认配置"])
        }
        return try WGConfigCodec.decode(try Data(contentsOf: configURL))
    }

    public func saveConfig(_ config: WGConfig) throws {
        try ensureDirectory()
        backUpIfPresent(configURL, label: "config")
        try WGConfigCodec.encode(config).write(to: configURL, options: .atomic)
        Log.config.notice("配置已保存：\(self.configURL.path, privacy: .public)")
    }

    // MARK: - Preferences

    public func loadPreferences() -> WGPreferences {
        guard fileManager.fileExists(atPath: preferencesURL.path),
              let data = try? Data(contentsOf: preferencesURL),
              let preferences = try? WGConfigCodec.decodePreferences(data)
        else { return WGPreferences() }
        return preferences
    }

    public func savePreferences(_ preferences: WGPreferences) throws {
        try ensureDirectory()
        backUpIfPresent(preferencesURL, label: "prefs")
        try WGConfigCodec.encodePreferences(preferences).write(to: preferencesURL, options: .atomic)
    }

    // MARK: - Backups

    /// Copies the file that is about to be overwritten into `Backups/`, keeping the newest
    /// `backupLimit` copies per label.
    ///
    /// A failure here is logged and swallowed on purpose: not being able to make a backup must not
    /// stop the user from saving.
    private func backUpIfPresent(_ url: URL, label: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Milliseconds, so that two saves in the same second still get distinct names. Keeping
            // names unique matters beyond tidiness: the listing and the pruning both rely on name
            // order being time order, and a *reused* name would be pruned as if it were the oldest
            // entry — which silently stopped backups from being kept at all.
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let stamp = formatter.string(from: Date())

            var target = backupsDirectory.appendingPathComponent("\(label)-\(stamp).json")
            var suffix = 2
            // Safety net for the (very unlikely) case of two saves in the same millisecond. The
            // suffix is zero-padded so that name order stays time order.
            while fileManager.fileExists(atPath: target.path) {
                target = backupsDirectory.appendingPathComponent(
                    String(format: "%@-%@-%02d.json", label, stamp, suffix)
                )
                suffix += 1
            }
            try fileManager.copyItem(at: url, to: target)
            pruneBackups(label: label)
        } catch {
            Log.config.error("配置备份失败（保存继续）：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps only the newest `backupLimit` backups for `label`.
    ///
    /// The timestamp format sorts lexicographically, so ordering by name is ordering by age.
    private func pruneBackups(label: String) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path) else { return }
        let mine = names
            .filter { $0.hasPrefix("\(label)-") && $0.hasSuffix(".json") }
            .sorted()
        guard mine.count > Self.backupLimit else { return }
        for name in mine.prefix(mine.count - Self.backupLimit) {
            try? fileManager.removeItem(at: backupsDirectory.appendingPathComponent(name))
        }
    }

    /// The backup files for `label`, newest first. Used by tests and by the settings window.
    public func backups(for label: String) -> [URL] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path) else { return [] }
        return names
            .filter { $0.hasPrefix("\(label)-") && $0.hasSuffix(".json") }
            .sorted(by: >)
            .map { backupsDirectory.appendingPathComponent($0) }
    }

    // MARK: - Import

    /// Reads the original app's configuration and copies it into zWGestures' storage.
    ///
    /// - Returns: the import result, including statistics and any warnings.
    @discardableResult
    public func importLegacyConfiguration(
        from directory: URL? = nil,
        savePreferences: Bool = true
    ) throws -> WGImportResult {
        guard let source = directory ?? LegacyConfigImporter.locateVersionDirectory() else {
            throw WGImportError.directoryNotFound
        }
        let result = try LegacyConfigImporter.load(from: source)

        try saveConfig(result.config)
        if savePreferences, let preferences = result.preferences {
            try self.savePreferences(preferences)
        }
        return result
    }

    // MARK: - Private

    private func ensureDirectory() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        Log.config.notice("已创建配置目录：\(self.directory.path, privacy: .public)")
    }
}
