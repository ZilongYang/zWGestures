import AppKit

/// A tiny always-on-top readout of what the input engine is doing.
///
/// P1 has no visible gesture trail yet, so this is how behaviour gets verified: the state
/// machine, the decisions it takes and the event counters are all visible while clicking
/// and drawing. Toggle it from the menu bar, or set `ZWG_DEBUG_HUD=1` to open it on launch.
///
/// The refresh loop is a `Task` rather than a `Timer` on purpose. A `Timer` block is a
/// `@Sendable` closure, so touching main-actor state from it forces the compiler to emit
/// `MainActor.assumeIsolated` — and that runtime check faulted (SIGBUS inside
/// `SerialExecutor.isMainExecutor`) and took the whole app down. A `Task` hops to the main
/// actor properly instead of asserting that it is already there.
@MainActor
final class DebugHUDWindow {
    private let coordinator: InputCoordinator
    private var window: NSPanel?
    private var label: NSTextField?
    private var refreshTask: Task<Void, Never>?

    private let refreshInterval = Duration.milliseconds(100)

    init(coordinator: InputCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = window ?? makePanel()
        window = panel
        refresh()
        startRefreshing()
        panel.orderFrontRegardless()
    }

    func hide() {
        stopRefreshing()
        window?.orderOut(nil)
    }

    // MARK: - Refresh loop

    private func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                do {
                    try await Task.sleep(for: self.refreshInterval)
                } catch {
                    return // cancelled
                }
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false

        let textField = NSTextField(labelWithString: "")
        textField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textField.textColor = .white
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            textField.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -8),
        ])
        panel.contentView = content
        label = textField

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 16, y: frame.minY + 16))
        }
        return panel
    }

    private func refresh() {
        let snapshot = coordinator.snapshot
        let state = snapshot.stateName
        let marker = switch state {
        case "drawing": "✏️"
        case "pending": "⏳"
        case "passthrough": "➡️"
        default: "·"
        }

        label?.stringValue = """
            \(marker) state      \(state)
            tap          \(snapshot.tapStatus)
            last effect  \(snapshot.lastEffect)
            events       \(snapshot.eventCount)   timeouts \(snapshot.timeoutCount)
            strokes      \(snapshot.gestureCount)   replays \(snapshot.replayCount)
            matched      \(snapshot.matchedCount)
            gesture      \(gestureDescription(snapshot))
            executed     \(snapshot.lastExecuted ?? "—")
            stroke pts   \(snapshot.strokePointCount)   长度 \(Int(snapshot.strokeLength))
            panic        \(PanicShortcut.displayName)
            """
    }

    private func gestureDescription(_ snapshot: InputSnapshot) -> String {
        if let name = snapshot.lastGestureName {
            let distance = snapshot.lastGestureDistance.map { String(format: "%.3f", $0) } ?? "-"
            return "「\(name)」 距离 \(distance)"
        }
        if snapshot.gestureCount > 0 {
            let nearest = snapshot.nearestGestureName ?? "无候选"
            let distance = snapshot.nearestGestureDistance.map { String(format: "%.3f", $0) } ?? "-"
            return "未识别（最近：\(nearest) \(distance)）"
        }
        return "—"
    }
}
