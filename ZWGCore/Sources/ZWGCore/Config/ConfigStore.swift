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

    /// Where "now" comes from when stamping a backup.
    ///
    /// Injectable so tests can pin the clock: the collision path below only triggers when two saves
    /// land in the same millisecond, and a test that merely saves in a tight loop therefore catches
    /// it **once every few runs** (it did: 1 in 8). Pinning the clock makes that path deterministic.
    var now: () -> Date = { Date() }

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

            // Two saves inside the same millisecond are resolved by **moving the timestamp forward
            // one millisecond at a time**, never by appending a suffix: a suffixed name such as
            // `…-263-02.json` sorts *before* `…-263.json` (because "-" < "."), which inverts name
            // order against time order and makes pruning drop the newer copy and keep the older one.
            // Every name must keep exactly the same shape for the ordering to hold.
            var date = nextStamp(for: label, formatter: formatter)
            var target = backupsDirectory.appendingPathComponent(
                "\(label)-\(formatter.string(from: date)).json"
            )
            var attempts = 0
            while fileManager.fileExists(atPath: target.path), attempts < 1000 {
                date = date.addingTimeInterval(0.001)
                target = backupsDirectory.appendingPathComponent(
                    "\(label)-\(formatter.string(from: date)).json"
                )
                attempts += 1
            }
            try fileManager.copyItem(at: url, to: target)
            pruneBackups(label: label)
        } catch {
            Log.config.error("配置备份失败（保存继续）：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// The stamp for the next backup: `now`, pushed strictly past the newest backup already on disk.
    ///
    /// **A name is never reused.** Pruning frees the *smallest* name, so a fresh backup that reused
    /// it would sort as the oldest entry and pruning would delete it immediately — backups silently
    /// stopped accumulating after the limit was first reached. That is what this guards against.
    /// (It only shows up when saves land in the same millisecond, which is why the setting window
    /// never hit it by hand — but "same millisecond" is exactly what a fast loop produces.)
    private func nextStamp(for label: String, formatter: DateFormatter) -> Date {
        let prefix = "\(label)-"
        let stamps = (try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path))?
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .compactMap { formatter.date(from: String($0.dropFirst(prefix.count).dropLast(5))) }
            ?? []
        let candidate = now()
        guard let newest = stamps.max(), candidate <= newest else { return candidate }
        return newest.addingTimeInterval(0.001)
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

    /// Seeds zWGestures' storage from the factory-default pack that ships inside the app bundle.
    ///
    /// Same shape as `importLegacyConfiguration` on purpose — the two sources differ only in where
    /// they come from, and `ConfigController` applies the same "the system owns the login item"
    /// correction to both. The directory is passed in rather than resolved here, so a test can drive
    /// the whole path without an app bundle.
    ///
    /// (`LegacyConfigImporter.load` reads any directory holding a `gestures.json` / `prefs.json` in
    /// the original's format; the bundled pack is exactly that. Its `sourceVersion` — the directory's
    /// own name — is not meaningful for this path and the caller does not use it.)
    @discardableResult
    public func importDefaultConfiguration(from directory: URL) throws -> WGImportResult {
        let result = try LegacyConfigImporter.load(from: directory)
        try saveConfig(result.config)
        if let preferences = result.preferences {
            try savePreferences(preferences)
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
