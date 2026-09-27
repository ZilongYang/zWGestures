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
    private var permissionTimer: Timer?
    private(set) var isRunning = false
    private(set) var lastFailureReason: String?

    /// Called whenever `isRunning` or the permission state may have changed.
    var onStateChange: (() -> Void)?

    init() {
        coordinator = InputCoordinator()
        coordinator.onPanic = { [weak self] in
            Task { @MainActor in
                self?.pause(reason: "急停快捷键 \(PanicShortcut.displayName)")
            }
        }
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
