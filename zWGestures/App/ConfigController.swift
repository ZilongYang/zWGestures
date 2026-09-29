import AppKit
import Foundation

/// Owns the gesture configuration: loads it from zWGestures' storage, and on first launch obtains one
/// from somewhere — the original app's installation if there is one, otherwise the default pack built
/// into this app.
@MainActor
final class ConfigController {
    enum Status: Equatable {
        case empty
        case loaded(intents: Int)
        case imported(intents: Int, version: String)
        /// Seeded from the gesture pack built into the app: the path a fresh download takes, where
        /// there is no WGestures installation to import from.
        case seeded(intents: Int)
        case failed(String)

        var localizedText: String {
            switch self {
            case .empty: "尚未导入配置"
            case .loaded(let intents): "配置已载入（\(intents) 条手势）"
            case .imported(let intents, let version): "已从 WGestures \(version) 导入 \(intents) 条手势"
            case .seeded(let intents): "已载入内置默认手势（\(intents) 条）"
            case .failed(let reason): "配置出错：\(reason)"
            }
        }
    }

    let store: ConfigStore
    private(set) var config = WGConfig()
    private(set) var preferences = WGPreferences()
    private(set) var status: Status = .empty
    private(set) var warnings: [String] = []

    var onStateChange: (() -> Void)?

    /// Reads the system's launch-at-login state.
    ///
    /// The login item is owned by the system, not by `prefs.json`: a re-import copies the
    /// original app's `AutoStart` over ours, which would silently disagree with the actual
    /// login item. Injecting this makes that interaction testable without touching the system.
    private let readLoginItem: () -> Bool
    /// Where the original app's configuration lives, if it is installed.
    private let locateLegacy: () -> URL?
    /// Where the default gesture pack lives inside this app's bundle.
    private let bundledDefaults: () -> URL?

    init(
        store: ConfigStore = ConfigStore(),
        readLoginItem: @escaping () -> Bool = { LoginItem().isEnabled },
        locateLegacy: @escaping () -> URL? = { LegacyConfigImporter.locateVersionDirectory() },
        bundledDefaults: @escaping () -> URL? = { ConfigController.bundledDefaultsDirectory }
    ) {
        self.store = store
        self.readLoginItem = readLoginItem
        self.locateLegacy = locateLegacy
        self.bundledDefaults = bundledDefaults
    }

    /// The factory-default pack inside the app bundle: `Contents/Resources/Defaults`.
    ///
    /// Returns `nil` when the directory is absent, so a packaging mistake degrades to "no gestures
    /// yet" — which the status line already reports — rather than a load error the user cannot act on.
    static var bundledDefaultsDirectory: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let directory = resources.appendingPathComponent("Defaults", isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    /// Total number of gestures across every target.
    var intentCount: Int {
        config.allTargets.reduce(0) { $0 + $1.intents.count }
    }

    /// Called once at launch. The ordering lives in `ConfigBootstrapper` so it can be tested.
    func start() {
        switch ConfigBootstrapper.decide(
            hasConfig: store.hasConfig,
            legacyDirectory: locateLegacy(),
            defaultsDirectory: bundledDefaults()
        ) {
        case .existingConfig:
            reload()
        case .legacyInstall(let directory):
            importLegacy(from: directory, loginItemWasEnabled: readLoginItem())
        case .factoryDefault(let directory):
            seedFromFactoryDefaults(at: directory, loginItemWasEnabled: readLoginItem())
        case nil:
            status = .empty
            warnings = ["既没有可用的配置，也没有内置默认手势包"]
            Log.config.error("没有配置也没有内置默认手势包，手势集为空")
        }
        onStateChange?()
    }

    func reload() {
        do {
            let result = try store.loadConfig()
            config = result.config
            warnings = result.warnings
            preferences = store.loadPreferences()
            status = .loaded(intents: intentCount)
        } catch {
            status = .failed(error.localizedDescription)
            Log.config.error("配置载入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-imports from the original app: the menu-bar item's 「从 WGestures 导入配置…」.
    ///
    /// Always re-reads the original's directory at that moment, so an installation that appeared or
    /// was updated after launch is picked up.
    func importLegacy() {
        importLegacy(from: locateLegacy(), loginItemWasEnabled: readLoginItem())
        onStateChange?()
    }

    private func importLegacy(from directory: URL?, loginItemWasEnabled: Bool) {
        do {
            let result = try store.importLegacyConfiguration(from: directory)
            config = result.config
            preferences = correctLoginItem(
                in: result.preferences ?? WGPreferences(),
                to: loginItemWasEnabled
            )
            warnings = result.warnings
            status = .imported(intents: intentCount, version: result.sourceVersion ?? "?")
            Log.config.notice("""
                已从 WGestures 导入配置：\
                \(result.statistics.summary, privacy: .public)
                """)
            logWarnings(result.warnings, what: "导入")
        } catch {
            recordFailure(error, during: "导入")
        }
    }

    /// First launch with no original installation to import from.
    private func seedFromFactoryDefaults(at directory: URL, loginItemWasEnabled: Bool) {
        do {
            let result = try store.importDefaultConfiguration(from: directory)
            config = result.config
            preferences = correctLoginItem(
                in: result.preferences ?? WGPreferences(),
                to: loginItemWasEnabled
            )
            warnings = result.warnings
            status = .seeded(intents: intentCount)
            Log.config.notice("""
                已载入内置默认手势：\
                \(result.statistics.summary, privacy: .public)
                """)
            logWarnings(result.warnings, what: "默认手势")
        } catch {
            recordFailure(error, during: "载入内置默认手势")
        }
    }

    /// Takes over a configuration that was edited elsewhere (currently the settings window) and
    /// has already been written to disk.
    func adopt(config newConfig: WGConfig) {
        config = newConfig
        warnings = []
        status = .loaded(intents: intentCount)
        onStateChange?()
    }

    /// Takes over preferences that were edited in the settings window and already written to disk.
    func adopt(preferences newPreferences: WGPreferences) {
        preferences = newPreferences
        onStateChange?()
    }

    /// Mirrors a preference that lives in the system (currently only the login item) back into
    /// `prefs.json`, so the next import/export stays consistent with reality.
    func update(autoStart: Bool) {
        guard preferences.autoStart != autoStart else { return }
        preferences.autoStart = autoStart
        do {
            try store.savePreferences(preferences)
        } catch {
            Log.config.error("偏好保存失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the outcome of a first-run import in an alert, so it is not buried in the log.
    func presentImportSummary() {
        let alert = NSAlert()
        alert.messageText = status.localizedText
        alert.alertStyle = warnings.isEmpty ? .informational : .warning
        alert.informativeText = summaryBody
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Private

    /// The system owns the login item, so the imported file's `AutoStart` is corrected to match it.
    ///
    /// Both sources — the original app's `prefs.json` and the bundled default pack — carry an
    /// `AutoStart` describing *their* intent. Writing that through would silently change this app's
    /// login item, so the system's state is read before the import and restored over the imported
    /// value.
    private func correctLoginItem(in imported: WGPreferences, to systemState: Bool) -> WGPreferences {
        guard imported.autoStart != systemState else { return imported }
        var corrected = imported
        corrected.autoStart = systemState
        try? store.savePreferences(corrected)
        Log.config.notice("""
            导入的 AutoStart 与系统登录项不一致，已保留系统状态：\
            \(systemState, privacy: .public)
            """)
        return corrected
    }

    private func recordFailure(_ error: Error, during what: String) {
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        status = .failed(reason)
        Log.config.error("\(what, privacy: .public)失败：\(reason, privacy: .public)")
    }

    private func logWarnings(_ warnings: [String], what: String) {
        for warning in warnings {
            Log.config.warning("\(what, privacy: .public)警告：\(warning, privacy: .public)")
        }
    }

    /// What a first-run alert says. The seeded case must not claim the user's own WGestures
    /// configuration came across — nothing was imported at all.
    private var summaryBody: String {
        if case .seeded = status {
            return """
                这是内置的默认手势包，取自原版 WGestures 的出厂手势集，名字已经译成中文。
                可以直接在设置里改，也可以随时从菜单栏「从 WGestures 导入配置…」导入你自己的。

                原版的配置目录只被读取，不会被修改。
                """
        }
        var body = "zWGestures 只读取原版配置，不会修改它。\n\n"
        body += warnings.isEmpty
            ? "所有对象类型都能识别，没有数据被丢弃。"
            : warnings.joined(separator: "\n")
        return body
    }
}
