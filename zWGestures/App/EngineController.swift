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

    /// `NSEvent` monitor tokens for the emergency-stop shortcut.
    private var panicMonitorGlobal: Any?
    private var panicMonitorLocal: Any?

    /// Called whenever `isRunning` or the permission state may have changed.
    var onStateChange: (() -> Void)?

    init(appDirectory: AppDirectory, startDragTimeout: TimeInterval = 0.25) {
        self.appDirectory = appDirectory
        coordinator = InputCoordinator(settings: EngineSettings(startDragTimeout: startDragTimeout))
        overlay = StrokeOverlayController(coordinator: coordinator)
        coordinator.onGestureMatched = { [weak self] outcome in
            Task { @MainActor in
                self?.run(outcome)
            }
        }
        coordinator.onTapGaveUp = { [weak self] timeoutCount in
            Task { @MainActor in
                self?.handleTapGiveUp(timeoutCount: timeoutCount)
            }
        }
        appDirectory.onChange = { [weak self] in
            self?.pushRecognitionContext()
        }
    }

    /// Applies the look of the trail from the imported preferences.
    func apply(overlayStyle: OverlayStyle) {
        self.overlayStyle = overlayStyle
        overlay.apply(style: overlayStyle)
    }

    private func run(_ outcome: GestureOutcome) {
        let plan = WGCommandPlanner.plan(outcome.match.intent.command)
        let context = ActionContextProvider.current(
            gestureStart: outcome.candidate.stroke.startPoint,
            application: outcome.target.application,
            windowID: outcome.windowID
        )
        executor.execute(plan: plan, intentName: outcome.match.name, context: context)
        coordinator.noteExecuted(WGCommandPlanner.summary(of: outcome.match.intent.command))
    }

    /// Applies the user's preference to the running engine.
    func apply(startDragTimeout: TimeInterval) {
        coordinator.engine.settings.startDragTimeout = startDragTimeout
    }

    /// Publishes the gesture sets, the targeting mode and the current application directory.
    func apply(config: WGConfig, targetMode: WGTargetMode) {
        self.config = config
        self.targetMode = targetMode
        pushRecognitionContext()
    }

    private func pushRecognitionContext() {
        coordinator.updateRecognition(RecognitionContext(
            config: config,
            targetMode: targetMode,
            applications: appDirectory.applications,
            focusedPID: appDirectory.focusedPID
        ))
    }

    var isPermitted: Bool { PermissionGate.isAccessibilityTrusted }

    /// Starts the engine if Accessibility has been granted, otherwise waits for the grant.
    func startIfPermitted() {
        guard isPermitted else {
            Log.app.notice("尚未获得辅助功能权限，暂不安装事件拦截器")
            lastFailureReason = "尚未获得辅助功能权限"
            isRunning = false
            startPermissionPolling()
            onStateChange?()
            return
        }

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
