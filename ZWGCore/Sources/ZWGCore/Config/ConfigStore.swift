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
        try WGConfigCodec.encodePreferences(preferences).write(to: preferencesURL, options: .atomic)
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
