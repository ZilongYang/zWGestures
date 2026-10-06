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
            case .notRegistered: L10n.text(.loginItemOff)
            case .enabled: L10n.text(.loginItemOn)
            case .requiresApproval: L10n.text(.loginItemPending)
            case .notFound: L10n.text(.loginItemNotFound)
            case .unknown: L10n.text(.loginItemUnknown)
            }
        }

        var isOn: Bool {
            switch self {
            case .enabled, .requiresApproval: true
            default: false
            }
        }
    }

    /// Which mechanism is actually keeping the app alive at login.
    enum Mechanism: Equatable {
        case none
        /// Registered through `SMAppService`; shows up in System Settings → Login Items.
        case serviceManagement
        /// The `~/Library/LaunchAgents` fallback (see `LaunchAgent`).
        case launchAgent

        var localizedName: String {
            switch self {
            case .none: L10n.text(.mechanismDisabled)
            case .serviceManagement: L10n.text(.mechanismLoginItem)
            case .launchAgent: "LaunchAgent"
            }
        }
    }

    /// The state that matters, taking the fallback into account.
    ///
    /// The launch agent is consulted first: when it is in place, autostart works regardless of what
    /// `SMAppService` thinks, and saying anything else would be misleading.
    var mechanism: Mechanism {
        launchAgentIsLoaded ? .launchAgent
            : (smAppServiceStatus == .enabled ? .serviceManagement : .none)
    }

    var status: Status {
        switch mechanism {
        case .launchAgent, .serviceManagement:
            return .enabled
        case .none:
            return smAppServiceStatus
        }
    }

    /// What `SMAppService` reports, which is what System Settings' pane will reflect.
    private var smAppServiceStatus: Status {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    var isEnabled: Bool { status.isOn }

    /// Turns autostart on or off.
    ///
    /// Enabling tries `SMAppService` first — when it works, the entry is visible in System Settings,
    /// which is nicer for the user. Because it cannot register this locally-signed app on this
    /// machine (`.notFound`, and BackgroundTaskManagement never records anything), the launch agent
    /// is installed instead. Disabling always clears **both**, so no stale agent is left behind.
    ///
    /// - Returns: `nil` on success, otherwise a human-readable reason for the failure.
    func setEnabled(_ enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    private func enable() -> String? {
        var serviceManagementFailure: String?
        do {
            try SMAppService.mainApp.register()
        } catch {
            serviceManagementFailure = error.localizedDescription
        }

        // `register()` can succeed and still leave `.notFound` — that is exactly what happens on
        // this machine — so the resulting status decides, not the absence of a thrown error.
        if smAppServiceStatus == .enabled || smAppServiceStatus == .requiresApproval {
            removeLaunchAgent()
            Log.app.notice("开机自启已开启（系统登录项）")
            return nil
        }

        if let failure = installLaunchAgent() {
            let smReason = serviceManagementFailure ?? "系统登录项报告 \(smAppServiceStatus)"
            Log.app.error("""
                开机自启两种机制都失败：系统登录项 \(smReason, privacy: .public)；\
                LaunchAgent \(failure, privacy: .public)
                """)
            return """
                系统登录项装不上（\(smReason)），LaunchAgent 兜底也失败：\(failure)
                """
        }

        Log.app.notice("""
            开机自启已开启（LaunchAgent 兜底；系统登录项报告 \
            \(String(describing: smAppServiceStatus), privacy: .public)）
            """)
        return nil
    }

    private func disable() -> String? {
        var problems: [String] = []
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            // Unregistering something that was never registered is not a failure worth reporting.
            Log.app.debug("注销系统登录项：\(error.localizedDescription, privacy: .public)")
        }
        if let failure = removeLaunchAgent() { problems.append(failure) }
        guard problems.isEmpty else { return problems.joined(separator: "；") }
        Log.app.notice("开机自启已关闭")
        return nil
    }

    // MARK: - LaunchAgent fallback

    /// Whether our agent is present **and** loaded.
    private var launchAgentIsLoaded: Bool {
        guard FileManager.default.fileExists(atPath: LaunchAgent.plistURL.path) else { return false }
        return runLaunchctl(["print", "gui/\(getuid())/\(LaunchAgent.label)"]).status == 0
    }

    /// - Returns: `nil` on success, otherwise the reason.
    private func installLaunchAgent() -> String? {
        do {
            try FileManager.default.createDirectory(
                at: LaunchAgent.plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try LaunchAgent.makePlist(appPath: Bundle.main.bundlePath)
                .write(to: LaunchAgent.plistURL, options: .atomic)
        } catch {
            return "写入 \(LaunchAgent.plistURL.path) 失败：\(error.localizedDescription)"
        }

        // `bootstrap` fails when the label is already loaded, so clear it first — that also makes
        // this idempotent if the file content changed.
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(LaunchAgent.label)"])
        let bootstrapped = runLaunchctl(["bootstrap", "gui/\(getuid())", LaunchAgent.plistURL.path])
        guard bootstrapped.status == 0 else {
            return "launchctl bootstrap 失败：\(bootstrapped.message)"
        }
        return nil
    }

    /// - Returns: `nil` on success, otherwise the reason.
    @discardableResult
    private func removeLaunchAgent() -> String? {
        guard FileManager.default.fileExists(atPath: LaunchAgent.plistURL.path) else { return nil }
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(LaunchAgent.label)"])
        do {
            try FileManager.default.removeItem(at: LaunchAgent.plistURL)
        } catch {
            return "删除 \(LaunchAgent.plistURL.path) 失败：\(error.localizedDescription)"
        }
        return nil
    }

    /// Runs `launchctl` and collects its status and output.
    private func runLaunchctl(_ arguments: [String]) -> (status: Int32, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, text.isEmpty ? "（无输出）" : text)
    }

    /// Opens the Login Items pane, for the `requiresApproval` case.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
