import AppKit
import Foundation

/// Keeps a thread-safe directory of running applications.
///
/// The gesture engine runs on the event-tap thread and must not call AppKit, so application
/// identities are collected here on the main thread and read from the tap thread through a
/// lock. Refresh is driven by workspace notifications (an app switch is reflected immediately)
/// with a slow timer as a safety net.
@MainActor
final class AppDirectory {
    private let lock = NSLock()
    private var byPID: [Int32: WGApplicationIdentity] = [:]
    private var focusedStorage: WGApplicationIdentity?

    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?

    private let refreshInterval = Duration.seconds(3)

    /// Invoked on the main actor whenever the directory changes.
    var onChange: (() -> Void)?

    func start() {
        refresh()
        observeWorkspace()
        startRefreshLoop()
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Reads (any thread)

    var focused: WGApplicationIdentity? {
        lock.withLock { focusedStorage }
    }

    func identity(for pid: Int32) -> WGApplicationIdentity? {
        lock.withLock { byPID[pid] }
    }

    /// A snapshot for the tap thread; main-actor reads only.
    var applications: [Int32: WGApplicationIdentity] {
        lock.withLock { byPID }
    }

    var focusedPID: Int32? { focused?.pid }

    // MARK: - Main actor

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Hops to the main actor properly instead of asserting that it is already
                // there: `MainActor.assumeIsolated` in a callback like this is what crashed the
                // app once. See the development conventions in README.md.
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
    }

    private func startRefreshLoop() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(for: self.refreshInterval)
                } catch {
                    return
                }
                self.refresh()
            }
        }
    }

    private func refresh() {
        let running = NSWorkspace.shared.runningApplications
        var next: [Int32: WGApplicationIdentity] = [:]
        next.reserveCapacity(running.count)
        for application in running {
            guard application.processIdentifier > 0 else { continue }
            next[application.processIdentifier] = WGApplicationIdentity(
                pid: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                executablePath: application.executableURL?.path,
                localizedName: application.localizedName
            )
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let changed = lock.withLock { () -> Bool in
            let focusedChanged = focusedStorage?.pid != frontmost
            let directoryChanged = next != byPID
            byPID = next
            focusedStorage = frontmost.flatMap { next[$0] }
            return focusedChanged || directoryChanged
        }

        if changed { onChange?() }
    }
}
