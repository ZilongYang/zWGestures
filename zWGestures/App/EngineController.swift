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

    private var permissionTimer: Timer?
    private(set) var isRunning = false
    private(set) var lastFailureReason: String?

    /// Called whenever `isRunning` or the permission state may have changed.
    var onStateChange: (() -> Void)?

    init(startDragTimeout: TimeInterval = 0.25) {
        coordinator = InputCoordinator(settings: EngineSettings(startDragTimeout: startDragTimeout))
        coordinator.onPanic = { [weak self] in
            Task { @MainActor in
                self?.pause(reason: "急停快捷键 \(PanicShortcut.displayName)")
            }
        }
        coordinator.onGestureMatched = { [weak self] match, candidate in
            let gestureStart = candidate.stroke.startPoint
            Task { @MainActor in
                self?.run(match: match, gestureStart: gestureStart)
            }
        }
    }

    private func run(match: RecognitionMatch, gestureStart: CGPoint) {
        let plan = WGCommandPlanner.plan(match.intent.command)
        let context = ActionContextProvider.current(gestureStart: gestureStart)
        executor.execute(plan: plan, intentName: match.name, context: context)
        coordinator.noteExecuted(WGCommandPlanner.summary(of: match.intent.command))
    }

    /// Applies the user's preference to the running engine.
    func apply(startDragTimeout: TimeInterval) {
        coordinator.engine.settings.startDragTimeout = startDragTimeout
    }

    /// Publishes the gesture set the engine matches against.
    func applyRecognition(config: WGConfig) {
        coordinator.updateRecognition(target: config.general)
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
        if !isRunning {
            startPermissionPolling()
        }
        onStateChange?()
    }

    func pause(reason: String) {
        Log.app.notice("暂停手势引擎：\(reason, privacy: .public)")
        coordinator.stop()
        isRunning = false
        onStateChange?()
    }

    func resume() {
        startIfPermitted()
    }

    func stop() {
        stopPermissionPolling()
        coordinator.stop()
        isRunning = false
    }

    // MARK: - Private

    /// Polls for the Accessibility grant so the engine comes up on its own once the user
    /// ticks the checkbox, without needing a relaunch.
    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.isPermitted else { return }
                self.startIfPermitted()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}
