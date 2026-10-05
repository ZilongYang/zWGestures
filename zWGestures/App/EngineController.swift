import AppKit
import Foundation

/// Owns the input engine's lifecycle: permission gating, start/stop, and the emergency
/// stop shortcut.
///
/// Pausing really does tear the event tap down, so a paused zWGestures is completely out of
/// the event path rather than merely ignoring what it sees.
@MainActor
final class EngineController {
    let coordinator: InputCoordinator
    /// Runs the actions of recognised gestures; lives on the main actor, never on the tap
    /// thread.
    let executor = CommandExecutor()

    private let appDirectory: AppDirectory
    private var config = WGConfig()
    private var targetMode: WGTargetMode = .focused
    private var overlayStyle = OverlayStyle()
    private let overlay: StrokeOverlayController

    private var permissionTask: Task<Void, Never>?
    private let pollInterval = Duration.seconds(2)
    private(set) var isRunning = false
    private(set) var lastFailureReason: String?

    /// Whether the Accessibility grant is missing, never given, or was taken away by an update.
    ///
    /// The distinction is the whole point: 「还没给」and 「更新弄丢了」need different explanations, and
    /// only the second one looks like a broken release.
    private(set) var grantState: AccessibilityGrantState = .notGrantedYet
    /// The explanation is worth showing once per launch, not once per poll tick.
    private var didPresentGrantLostAlert = false

    /// Remembers that this install has run with the grant before — which is what makes the
    /// "an update took it away" case distinguishable from a first run.
    private let permissionHistory: PermissionHistory

    /// `NSEvent` monitor tokens for the emergency-stop shortcut.
    private var panicMonitorGlobal: Any?
    private var panicMonitorLocal: Any?

    /// Called whenever `isRunning` or the permission state may have changed.
    var onStateChange: (() -> Void)?

    init(
        appDirectory: AppDirectory,
        startDragTimeout: TimeInterval = 0.25,
        permissionHistory: PermissionHistory = PermissionHistory()
    ) {
        self.appDirectory = appDirectory
        self.permissionHistory = permissionHistory
        coordinator = InputCoordinator(settings: EngineSettings(startDragTimeout: startDragTimeout))
        overlay = StrokeOverlayController(coordinator: coordinator)
        coordinator.onGestureMatched = { [weak self] outcome in
            Task { @MainActor in
                await self?.run(outcome)
            }
        }
        coordinator.onTapGaveUp = { [weak self] timeoutCount in
            Task { @MainActor in
                self?.handleTapGiveUp(timeoutCount: timeoutCount)
            }
        }
        appDirectory.onChange = { [weak self] in
            self?.pushTargeting()
        }
    }

    /// Applies the look of the trail from the imported preferences.
    func apply(overlayStyle: OverlayStyle) {
        self.overlayStyle = overlayStyle
        overlay.apply(style: overlayStyle)
    }

    private func run(_ outcome: GestureOutcome) async {
        // 时间戳在拦截器线程上取，这里量的是「识别完成 → 主线程开始执行」这一段 —— 用户感觉
        // 「松手后动作慢半拍」量的就是它。
        coordinator.noteRecognizedToExecution(since: outcome.recognizedAt)
        let plan = WGCommandPlanner.plan(outcome.match.intent.command)
        var context = ActionContextProvider.current(
            gestureStart: outcome.candidate.stroke.startPoint,
            application: outcome.target.application,
            windowID: outcome.windowID
        )
        // 窗口标题走辅助功能 API，是**跨进程**调用：目标应用一旦无响应，它会把调用方阻塞数秒到
        // 数十秒。2026-10-06 就是这样把主线程卡了 47 秒（ROADMAP §22）。所以只有 shell 脚本
        // 真正需要 `WG_TARGET_WIN_NAME` 时才去取，而且在后台取、带 0.25 秒超时。
        if plan.needsTargetWindowTitle, let pid = context.targetPID {
            context.targetWindowName = await ActionContextProvider.windowTitle(for: pid)
        }
        executor.execute(plan: plan, intentName: outcome.match.name, context: context)
        coordinator.noteExecuted(WGCommandPlanner.summary(of: outcome.match.intent.command))
    }

    /// Applies the user's preference to the running engine.
    func apply(startDragTimeout: TimeInterval) {
        coordinator.engine.settings.startDragTimeout = startDragTimeout
    }

    /// Publishes the gesture sets and the targeting mode.
    ///
    /// The rule set changed, so the recognition index has to be rebuilt — that is the expensive
    /// path, and `InputCoordinator` takes it off the main actor.
    func apply(config: WGConfig, targetMode: WGTargetMode) {
        self.config = config
        self.targetMode = targetMode
        pushRecognitionContext(rulesChanged: true)
    }

    /// Only the targeting picture changed (an application started/stopped or focus moved).
    ///
    /// Deliberately does **not** touch the index: this runs every three seconds, and the index does
    /// not depend on it.
    private func pushTargeting() {
        pushRecognitionContext(rulesChanged: false)
    }

    private func pushRecognitionContext(rulesChanged: Bool) {
        let context = RecognitionContext(
            config: config,
            targetMode: targetMode,
            applications: appDirectory.applications,
            focusedPID: appDirectory.focusedPID
        )
        if rulesChanged {
            coordinator.applyConfiguration(context)
        } else {
            coordinator.updateTargeting(context)
        }
    }

    var isPermitted: Bool { PermissionGate.isAccessibilityTrusted }

    /// Starts the engine if Accessibility has been granted, otherwise waits for the grant.
    func startIfPermitted() {
        grantState = AccessibilityGrantAssessment.assess(
            isTrusted: isPermitted,
            hasEverRunGranted: permissionHistory.hasEverRunGranted
        )

        guard isPermitted else {
            switch grantState {
            case .lostAfterUpdate:
                Log.app.error("辅助功能授权已失效（更新后未重新授权的典型表现），不安装事件拦截器")
                lastFailureReason = "辅助功能授权已失效，需要重新授权"
            default:
                Log.app.notice("尚未获得辅助功能权限，暂不安装事件拦截器")
                lastFailureReason = "尚未获得辅助功能权限"
            }
            isRunning = false
            startPermissionPolling()
            onStateChange?()
            return
        }

        permissionHistory.recordGranted()
        stopPermissionPolling()
        isRunning = coordinator.start()
        lastFailureReason = isRunning ? nil : "事件拦截器安装失败"
        if isRunning {
            overlay.start()
            startPanicMonitors()
        } else {
            startPermissionPolling()
        }
        onStateChange?()
    }

    func pause(reason: String) {
        Log.app.notice("暂停手势引擎：\(reason, privacy: .public)")
        stopPanicMonitors()
        overlay.stop()
        coordinator.stop()
        isRunning = false
        lastFailureReason = reason
        onStateChange?()
    }

    func resume() {
        startIfPermitted()
    }

    func stop() {
        stopPermissionPolling()
        stopPanicMonitors()
        overlay.stop()
        coordinator.stop()
        isRunning = false
    }

    // MARK: - Accessibility grant

    /// Explains, at most once per launch, that an update took the Accessibility grant away.
    ///
    /// Worth a dialog of its own because this failure looks exactly like a broken release: the app is
    /// running, the menu-bar icon is there, and drawing a gesture does nothing at all. Called once
    /// from `AppDelegate` rather than from the permission poll — a poll that pops a modal alert every
    /// two seconds would be its own bug.
    func presentGrantLostAlertIfNeeded() {
        guard grantState == .lostAfterUpdate, !didPresentGrantLostAlert else { return }
        didPresentGrantLostAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "辅助功能授权已失效，画手势不会有反应"
        alert.informativeText = """
            这通常发生在更新之后：这个版本没有 Apple 开发者签名，系统按版本指纹识别它，\
            所以每次更新都要重新授权一次。

            请在「系统设置 › 隐私与安全性 › 辅助功能」里重新勾选 zWGestures。\
            如果列表里已经勾着，先取消再勾上。

            授权之后手势引擎会自动启动，不需要重启应用。
            """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionGate.openAccessibilitySettings()
        }
    }

    // MARK: - Emergency stop
    //
    // The shortcut is watched with `NSEvent` monitors rather than through the event tap.
    //
    // Keeping the keyboard out of the tap matters: a `.defaultTap` sits in the synchronous path of
    // every event it is interested in, and keyboard events cannot be coalesced the way pointer
    // motion can. A callback that missed the system's deadline made typing impossible
    // machine-wide, and the only way out was a forced power-off. These monitors are listen-only by
    // construction, so they can never do that — and they also keep working when the tap itself is
    // the thing that went wrong.

    private func startPanicMonitors() {
        guard panicMonitorGlobal == nil else { return }

        panicMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Read the primitives before hopping to the main actor: `NSEvent` is not `Sendable`.
            let keyCode = event.keyCode
            let flags = event.modifierFlags.rawValue
            guard PanicShortcut.matches(keyCode: keyCode, modifierFlags: flags) else { return }
            Task { @MainActor [weak self] in
                self?.firePanicShortcut()
            }
        }

        // A global monitor does not see events destined for our own windows, and the settings
        // window can be key, so watch locally as well.
        panicMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.rawValue
            guard PanicShortcut.matches(keyCode: keyCode, modifierFlags: flags) else { return event }
            Task { @MainActor [weak self] in
                self?.firePanicShortcut()
            }
            return event
        }
    }

    private func stopPanicMonitors() {
        if let panicMonitorGlobal {
            NSEvent.removeMonitor(panicMonitorGlobal)
        }
        if let panicMonitorLocal {
            NSEvent.removeMonitor(panicMonitorLocal)
        }
        panicMonitorGlobal = nil
        panicMonitorLocal = nil
    }

    private func firePanicShortcut() {
        // Auto-repeat while the keys are held would otherwise fire this repeatedly.
        guard isRunning else { return }
        pause(reason: "急停快捷键 \(PanicShortcut.displayName)")
    }

    // MARK: - Slow-tap self-protection

    /// The tap tore itself down because its callback kept missing the system's deadline.
    ///
    /// Deliberately does **not** restart it and does **not** start the permission poll: the poll
    /// would bring the engine straight back up and put the system back into a slow tap. Recovery is
    /// a deliberate action from the menu.
    private func handleTapGiveUp(timeoutCount: Int) {
        Log.app.error("""
            事件拦截器连续超时 \(timeoutCount, privacy: .public) 次，已主动停用
            """)
        stopPermissionPolling()
        stopPanicMonitors()
        overlay.stop()
        isRunning = false
        lastFailureReason = EventTapHealthPolicy.failureReason(count: timeoutCount)
        onStateChange?()
        presentSlowCallbackAlert(timeoutCount: timeoutCount)
    }

    private func presentSlowCallbackAlert(timeoutCount: Int) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "手势引擎已自动停用"
        alert.informativeText = """
            事件拦截器在短时间内连续 \(timeoutCount) 次没能及时响应系统。\
            一个响应不及时的拦截器会拖慢整台电脑的键盘和鼠标输入，严重时只能强制关机。

            为避免影响你正常使用，zWGestures 已经停用手势引擎，键盘鼠标现在应当恢复正常。

            可以稍后从菜单栏「继续手势引擎」重新启用。若反复出现，请把这个现象反馈到项目 issue。
            """
        alert.addButton(withTitle: "保持停用")
        alert.addButton(withTitle: "重新启用")
        if alert.runModal() == .alertSecondButtonReturn {
            resume()
        }
    }

    // MARK: - Private

    /// Polls for the Accessibility grant so the engine comes up on its own once the user
    /// ticks the checkbox, without needing a relaunch.
    ///
    /// A `Task` loop rather than a `Timer`: see `DebugHUDWindow` for why `Timer` blocks force
    /// `MainActor.assumeIsolated` and how that faulted.
    private func startPermissionPolling() {
        guard permissionTask == nil else { return }
        permissionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self?.pollInterval ?? .seconds(2))
                } catch {
                    return // cancelled
                }
                guard let self else { return }
                if self.isPermitted {
                    self.stopPermissionPolling()
                    self.startIfPermitted()
                    return
                }
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTask?.cancel()
        permissionTask = nil
    }
}
