import AppKit
import CoreGraphics
import Foundation

/// Draws the gesture trail and the recognised gesture's name.
///
/// One panel per screen, above everything including full-screen applications, and completely
/// transparent to the mouse. The trail is redrawn from a `Task` loop rather than a `Timer`
/// because `Timer` blocks would force `MainActor.assumeIsolated`, which has crashed this app
/// before (see the development conventions in README.md).
@MainActor
final class StrokeOverlayController {
    private let coordinator: InputCoordinator
    private var style: OverlayStyle

    private var panels: [OverlayPanel] = []
    private var refreshTask: Task<Void, Never>?

    private var state = OverlayState()
    private var lastSequence = 0
    /// Time the last stroke finished, used to drive the hold-then-fade animation.
    private var completedAt: TimeInterval?

    /// How long the finished trail stays fully visible before fading.
    private let holdDuration: TimeInterval = 0.45
    /// How long the fade takes.
    private let fadeDuration: TimeInterval = 0.5
    private let refreshInterval = Duration.milliseconds(16)

    init(coordinator: InputCoordinator, style: OverlayStyle = OverlayStyle()) {
        self.coordinator = coordinator
        self.style = style
    }

    func apply(style: OverlayStyle) {
        self.style = style
        updatePanelVisibility()
    }

    func start() {
        guard refreshTask == nil else { return }
        rebuildPanels()
        observeScreenChanges()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                do {
                    try await Task.sleep(for: self.refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }

    // MARK: - Screens

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildPanels()
            }
        }
    }

    private func rebuildPanels() {
        for panel in panels { panel.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            OverlayPanel(screen: screen)
        }
        updatePanelVisibility()
    }

    private func updatePanelVisibility() {
        let shouldShow = style.showPath
        for panel in panels where shouldShow && !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Refresh

    private func refresh() {
        let next = coordinator.overlayState()
        if next.completionSequence != lastSequence {
            lastSequence = next.completionSequence
            completedAt = MonotonicClock.now
        }
        state = next

        let alpha = trailAlpha()
        let needsDrawing = style.showPath && !state.isEmpty && alpha > 0
        for panel in panels {
            panel.view.update(state: state, style: style, alpha: alpha)
            panel.view.needsDisplay = needsDrawing
        }
    }

    /// Full opacity while drawing and right after finishing, then fading out.
    private func trailAlpha() -> CGFloat {
        switch state.phase {
        case .idle:
            return 0
        case .drawing:
            return 1
        case .matched, .unmatched:
            guard let completedAt else { return 1 }
            let elapsed = MonotonicClock.now - completedAt
            if elapsed <= holdDuration { return 1 }
            let fade = (elapsed - holdDuration) / fadeDuration
            return CGFloat(max(0, 1 - fade))
        }
    }
}

// MARK: - Panel

private final class OverlayPanel: NSPanel {
    let screenReference: NSScreen
    let view: TrailView

    init(screen: NSScreen) {
        screenReference = screen
        view = TrailView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        // Above full-screen applications and the menu bar's own level.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

private final class TrailView: NSView {
    private var state = OverlayState()
    private var style = OverlayStyle()
    private var alpha: CGFloat = 1

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(state: OverlayState, style: OverlayStyle, alpha: CGFloat) {
        self.state = state
        self.style = style
        self.alpha = alpha
    }

    override func draw(_ dirtyRect: NSRect) {
        guard alpha > 0, !state.points.isEmpty, let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(style.lineWidth)

        let recognized = state.phase == .matched
        let color = recognized ? style.pathColorRecognized : style.pathColorNormal
        context.setStrokeColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha * alpha)

        let points = state.points.map(localPoint(fromCG:))
        guard points.count > 1 else { return }
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        if style.showGestureName, let name = state.gestureName, !name.isEmpty {
            drawLabel(name, recognized: recognized, recognizedColor: color)
        }
    }

    private func drawLabel(_ name: String, recognized: Bool, recognizedColor: WGColor) {
        let labelColor = recognized ? style.labelColorExecuted : style.labelColorNormal
        let color = NSColor(
            srgbRed: labelColor.red,
            green: labelColor.green,
            blue: labelColor.blue,
            alpha: labelColor.alpha * alpha
        )
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45 * alpha)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: color,
            .shadow: shadow,
        ]
        let text = NSAttributedString(string: name, attributes: attributes)
        let size = text.size()
        let centerY = localY(fromCGY: style.labelCenterY(screenHeight: primaryScreenHeight))
        let origin = CGPoint(
            x: bounds.midX - size.width / 2,
            y: centerY - size.height / 2
        )
        text.draw(at: origin)
    }

    // MARK: - Coordinates

    /// CG global coordinates put the origin at the top-left of the primary display; AppKit puts
    /// it at the bottom-left. The overlay is the only place that has to know this.
    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? (window?.screen?.frame.maxY ?? bounds.height)
    }

    private func localPoint(fromCG point: CGPoint) -> CGPoint {
        let windowOrigin = window?.frame.origin ?? .zero
        return CGPoint(
            x: point.x - windowOrigin.x,
            y: (primaryScreenHeight - point.y) - windowOrigin.y
        )
    }

    private func localY(fromCGY y: CGFloat) -> CGFloat {
        let windowOrigin = window?.frame.origin.y ?? 0
        return (primaryScreenHeight - y) - windowOrigin
    }
}
