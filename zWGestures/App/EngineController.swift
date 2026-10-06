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
    /// 急停快捷键的处理器是文件作用域函数，它通过这条通知把「按键匹配上了」交给主 actor。
    private var panicObserver: NSObjectProtocol?

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

        // 每一步都计时：这条链路上出过一次 47 秒和一次约一分钟的卡顿（ROADMAP 第 22、23 节），
        // 两次都得靠推断定位。留痕之后，下次日志会直接点名是哪一步。
        var step = MonotonicClock.now
        var slow: [String] = []
        func mark(_ name: String) {
            let now = MonotonicClock.now
            let milliseconds = (now - step) * 1000
            if milliseconds > 50 { slow.append("\(name) \(Int(milliseconds))ms") }
            step = now
        }

        let plan = WGCommandPlanner.plan(outcome.match.intent.command)
        mark("规划动作")

        var context = ActionContextProvider.current(
            gestureStart: outcome.candidate.stroke.startPoint,
            application: outcome.target.application,
            windowID: outcome.windowID
        )
        mark("构造上下文")

        // 窗口标题走辅助功能 API，是**跨进程**调用：目标应用一旦无响应，它会把调用方阻塞数秒到
        // 数十秒。2026-10-06 就是这样把主线程卡了 47 秒（ROADMAP §22）。所以只有 shell 脚本
        // 真正需要 `WG_TARGET_WIN_NAME` 时才去取，而且在后台取、带 0.25 秒超时。
        if plan.needsTargetWindowTitle, let pid = context.targetPID {
            context.targetWindowName = await ActionContextProvider.windowTitle(for: pid)
        }
        mark("取窗口标题")

        executor.execute(plan: plan, intentName: outcome.match.name, context: context)
        mark("执行动作")

        if !slow.isEmpty {
            Log.action.warning("""
                手势「\(outcome.match.name, privacy: .public)」的执行链路有慢步骤：\
                \(slow.joined(separator: "、"), privacy: .public)
                """)
        }

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
                lastFailureReason = L10n.text(.enginePermissionLost)
            default:
                Log.app.notice("尚未获得辅助功能权限，暂不安装事件拦截器")
                lastFailureReason = L10n.text(.enginePermissionMissing)
            }
            isRunning = false
            startPermissionPolling()
            onStateChange?()
            return
        }

        permissionHistory.recordGranted()
        stopPermissionPolling()
        isRunning = coordinator.start()
        lastFailureReason = isRunning ? nil : L10n.text(.engineTapInstallFailed)
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
        alert.messageText = L10n.text(.enginePermissionLost)
        alert.informativeText = """
            这通常发生在更新之后：这个版本没有 Apple 开发者签名，系统按版本指纹识别它，\
            所以每次更新都要重新授权一次。

            请在「系统设置 › 隐私与安全性 › 辅助功能」里重新勾选 zWGestures。\
            如果列表里已经勾着，先取消再勾上。

            授权之后手势引擎会自动启动，不需要重启应用。
            """
        alert.addButton(withTitle: L10n.text(.engineOpenSystemSettings))
        alert.addButton(withTitle: L10n.text(.engineLater))
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

        // 主 actor 这一侧只接收通知：`NotificationCenter` 的 block 是 `@Sendable`、不继承隔离，
        // 再用 `Task` 正常跳回主 actor —— 这个组合在本工程已验证可用（见 AppDirectory）。
        // 处理器本身必须是文件作用域函数，理由见 `handlePanicKeyEvent` 的注释。
        panicObserver = NotificationCenter.default.addObserver(
            forName: .zwgPanicShortcutPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.firePanicShortcut()
            }
        }

        panicMonitorGlobal = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown,
            handler: handlePanicKeyEvent
        )

        // A global monitor does not see events destined for our own windows, and the settings
        // window can be key, so watch locally as well.
        panicMonitorLocal = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: handlePanicKeyEventLocally
        )
    }

    private func stopPanicMonitors() {
        if let panicMonitorGlobal {
            NSEvent.removeMonitor(panicMonitorGlobal)
        }
        if let panicMonitorLocal {
            NSEvent.removeMonitor(panicMonitorLocal)
        }
        if let panicObserver {
            NotificationCenter.default.removeObserver(panicObserver)
        }
        panicMonitorGlobal = nil
        panicMonitorLocal = nil
        panicObserver = nil
    }

    private func firePanicShortcut() {
        // Auto-repeat while the keys are held would otherwise fire this repeatedly.
        guard isRunning else { return }
        pause(reason: L10n.format(.aboutPanicShortcutFormat, PanicShortcut.displayName))
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
        alert.messageText = L10n.text(.engineAutoDisabled)
        alert.informativeText = """
            事件拦截器在短时间内连续 \(timeoutCount) 次没能及时响应系统。\
            一个响应不及时的拦截器会拖慢整台电脑的键盘和鼠标输入，严重时只能强制关机。

            为避免影响你正常使用，zWGestures 已经停用手势引擎，键盘鼠标现在应当恢复正常。

            可以稍后从菜单栏「继续手势引擎」重新启用。若反复出现，请把这个现象反馈到项目 issue。
            """
        alert.addButton(withTitle: L10n.text(.engineStayDisabled))
        alert.addButton(withTitle: L10n.text(.engineReEnable))
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

// MARK: - 急停快捷键的按键处理器（必须是文件作用域函数）

extension Notification.Name {
    /// 文件作用域的按键处理器发现有人按了急停快捷键时发出，由 `EngineController` 在主 actor 上接收。
    static let zwgPanicShortcutPressed = Notification.Name(
        "io.github.zilongyang.zwgestures.panicShortcutPressed"
    )
}

/// 全局监听：只做「原始值是否匹配」，匹配就发个通知。
///
/// 🔴 **必须是文件作用域的非隔离函数 —— 不要写成 `@MainActor` 方法里的闭包字面量。**
/// `NSEvent.addGlobalMonitorForEvents` 的 handler 参数是普通的 `@escaping (NSEvent) -> Void`
/// （不是 `@Sendable`），所以在 `@MainActor` 方法里写的闭包字面量会**继承主 actor 隔离**，
/// 于是编译器给 AppKit 的回调插一个 `MainActor.assumeIsolated` thunk；而 AppKit 从 HIToolbox 的
/// 事件派发路径（`AppKit GlobalObserverHandler`）调用它时，那个检查自己 fault：
///
///     crash report zWGestures-2026-10-06-030632.ips
///     EXC_BAD_ACCESS / SIGSEGV (KERN_INVALID_ADDRESS at 0x0)
///       closure #1 in EngineController.startPanicMonitors()
///       → swift_getObjectType → swift_task_isMainExecutorImpl → isMainExecutor()
///       ← AppKit GlobalObserverHandler ← HIToolbox DispatchEventToHandlers
///
/// 文件作用域函数不继承任何隔离，所以不会插检查。见 docs/ROADMAP.md 第 8、22、23 节。
private func handlePanicKeyEvent(_ event: NSEvent) {
    guard isPanicShortcutKey(event) else { return }
    NotificationCenter.default.post(name: .zwgPanicShortcutPressed, object: nil)
}

/// 本地监听：**永远把事件交还**（本工程的急停监听结构上不吞事件），匹配上时额外发个通知。
private func handlePanicKeyEventLocally(_ event: NSEvent) -> NSEvent? {
    if isPanicShortcutKey(event) {
        NotificationCenter.default.post(name: .zwgPanicShortcutPressed, object: nil)
    }
    return event
}

/// 是否命中的急停快捷键。
///
/// **我们自己合成的按键一律不算**：Web 搜索为了读选中文字会合成 ⌘C，每条按键手势也会合成按键，
/// 它们打到我们自己的监听器上既没有意义，又正好会把上面那条崩溃路径引出来 ——
/// 2026-10-06 的两次事故都发生在 Web 搜索手势之后。
private func isPanicShortcutKey(_ event: NSEvent) -> Bool {
    if let cgEvent = event.cgEvent, SyntheticEventPoster.isSynthetic(cgEvent) {
        return false
    }
    return PanicShortcut.matches(
        keyCode: event.keyCode,
        modifierFlags: event.modifierFlags.rawValue
    )
}
