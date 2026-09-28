import ServiceManagement

/// Launch-at-login, backed by `SMAppService.mainApp`.
///
/// The truth lives in the system, not in `prefs.json`: the user can revoke the login item
/// from System Settings behind our back, so every read here asks `SMAppService` and the
/// preference is only written *after* a registration actually succeeded.
///
/// Note that a login item records the **path** of the bundle it was registered from. Running
/// straight out of `build/Build/Products/Debug` works, but `make clean` (or moving the app)
/// invalidates the entry — hence `make install` into `/Applications`.
@MainActor
struct LoginItem {
    enum Status: Equatable {
        case notRegistered
        case enabled
        /// macOS wants the user to confirm the switch in System Settings before it takes effect.
        case requiresApproval
        case notFound
        case unknown

        var localizedText: String {
            switch self {
            case .notRegistered: "开机不自动启动"
            case .enabled: "开机自动启动：已开启"
            case .requiresApproval: "开机自动启动：等待系统设置里确认"
            case .notFound: "开机自动启动：系统找不到该应用"
            case .unknown: "开机自动启动：状态未知"
            }
        }

        var isOn: Bool {
            switch self {
            case .enabled, .requiresApproval: true
            default: false
            }
        }
    }

    /// The number of the bundle's login item in System Settings' Login Items list.
    var status: Status {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    var isEnabled: Bool { status.isOn }

    /// - Returns: `nil` on success, otherwise a human-readable reason for the failure.
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let reason = error.localizedDescription
            Log.app.error("""
                设置开机自启（\(enabled ? "开启" : "关闭", privacy: .public)）失败：\
                \(reason, privacy: .public)
                """)
            return reason
        }
        let now = status
        Log.app.notice("""
            开机自启已设置为 \(enabled ? "开启" : "关闭", privacy: .public)，\
            系统状态：\(String(describing: now), privacy: .public)
            """)
        return nil
    }

    /// Opens the Login Items pane, for the `requiresApproval` case.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
