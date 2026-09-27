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

    /// Called whenever `isRunning` or the permission state may have changed.
    var onStateChange: (() -> Void)?

    init(appDirectory: AppDirectory, startDragTimeout: TimeInterval = 0.25) {
        self.appDirectory = appDirectory
        coordinator = InputCoordinator(settings: EngineSettings(startDragTimeout: startDragTimeout))
        overlay = StrokeOverlayController(coordinator: coordinator)
        coordinator.onPanic = { [weak self] in
            Task { @MainActor in
                self?.pause(reason: "急停快捷键 \(PanicShortcut.displayName)")
            }
        }
        coordinator.onGestureMatched = { [weak self] outcome in
            Task { @MainActor in
                self?.run(outcome)
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
        } else {
            startPermissionPolling()
        }
        onStateChange?()
    }

    func pause(reason: String) {
        Log.app.notice("暂停手势引擎：\(reason, privacy: .public)")
        overlay.stop()
        coordinator.stop()
        isRunning = false
        onStateChange?()
    }

    func resume() {
        startIfPermitted()
    }

    func stop() {
        stopPermissionPolling()
        overlay.stop()
        coordinator.stop()
        isRunning = false
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
