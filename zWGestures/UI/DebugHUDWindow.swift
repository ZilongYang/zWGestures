import AppKit

/// A tiny always-on-top readout of what the input engine is doing.
///
/// P1 has no visible gesture trail yet, so this is how behaviour gets verified: the state
/// machine, the decisions it takes and the event counters are all visible while clicking
/// and drawing. Toggle it from the menu bar, or set `ZWG_DEBUG_HUD=1` to open it on launch.
@MainActor
final class DebugHUDWindow {
    private let coordinator: InputCoordinator
    private var window: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refresh()
            }
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
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
            gestures     \(snapshot.gestureCount)   replays \(snapshot.replayCount)
            stroke pts   \(snapshot.strokePointCount)
            from  \(Int(snapshot.strokeStart.x)),\(Int(snapshot.strokeStart.y))
            to    \(Int(snapshot.strokeEnd.x)),\(Int(snapshot.strokeEnd.y))
            panic        \(PanicShortcut.displayName)
            """
    }
}
