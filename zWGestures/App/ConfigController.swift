import AppKit
import Foundation

/// Owns the gesture configuration: loads it from zWGestures' storage, and on first launch
/// migrates whatever the original WGestures installation had.
@MainActor
final class ConfigController {
    enum Status: Equatable {
        case empty
        case loaded(intents: Int)
        case imported(intents: Int, version: String)
        case failed(String)

        var localizedText: String {
            switch self {
            case .empty: "尚未导入配置"
            case .loaded(let intents): "配置已载入（\(intents) 条手势）"
            case .imported(let intents, let version): "已从 WGestures \(version) 导入 \(intents) 条手势"
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

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
    }

    /// Total number of gestures across every target.
    var intentCount: Int {
        config.allTargets.reduce(0) { $0 + $1.intents.count }
    }

    /// Called once at launch: use the stored configuration, or migrate the legacy one.
    func start() {
        if store.hasConfig {
            reload()
        } else {
            importLegacy()
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

    func importLegacy() {
        do {
            let result = try store.importLegacyConfiguration()
            config = result.config
            preferences = result.preferences ?? WGPreferences()
            warnings = result.warnings
            status = .imported(intents: intentCount, version: result.sourceVersion ?? "?")
            Log.config.notice("""
                已从 WGestures 导入配置：\
                \(result.statistics.summary, privacy: .public)
                """)
            for warning in result.warnings {
                Log.config.warning("导入警告：\(warning, privacy: .public)")
            }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed(reason)
            Log.config.error("导入失败：\(reason, privacy: .public)")
        }
        onStateChange?()
    }

    /// Shows the import summary in an alert, so the result is not buried in the log.
    func presentImportSummary() {
        let alert = NSAlert()
        alert.messageText = status.localizedText
        alert.alertStyle = warnings.isEmpty ? .informational : .warning
        var body = "zWGestures 只读取原版配置，不会修改它。\n\n"
        if warnings.isEmpty {
            body += "所有对象类型都能识别，没有数据被丢弃。"
        } else {
            body += warnings.joined(separator: "\n")
        }
        alert.informativeText = body
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
