import AppKit
import SwiftUI

/// The drawing surface used both inside the settings sheet and as a full-screen recorder.
///
/// The view is **flipped**, so its coordinates match screen orientation (y downwards) — which is
/// exactly the input `WGStrokeRecorder` documents. Keeping the two in the same orientation removes
/// the one conversion step that has historically gone wrong in this project.
///
/// Right-dragging draws too, not a context menu: `menu(for:)` returns `nil` and the right-mouse
/// events are handled here. That works because the settings window pauses the gesture engine while
/// the editor is open, so the global event tap is not competing for the right button.
final class StrokeCanvasNSView: NSView {
    enum Style {
        /// Inside the sheet: a bordered box, light trail.
        case embedded
        /// Full screen: dims everything and draws the trail boldly, like the real gesture overlay.
        case fullScreen
    }

    var style: Style = .embedded {
        didSet { needsDisplay = true }
    }

    /// Called when a stroke is finished (mouse up).
    var onFinish: (([CGPoint]) -> Void)?
    /// Called continuously while drawing, for the live direction preview.
    var onLiveChange: (([CGPoint]) -> Void)?
    /// Called on Escape.
    var onCancel: (() -> Void)?
    /// A message to draw on top, e.g. why the last drawing was rejected.
    var message: String? {
        didSet { needsDisplay = true }
    }

    private(set) var points: [CGPoint] = []
    private var isDrawing = false

    // AppKit calls these from geometry and hit-testing paths, so they are `nonisolated`: an
    // isolated override would run the runtime's main-actor check inside those paths, which has
    // already crashed this app once (see `TrailView.isFlipped`).
    nonisolated override var isFlipped: Bool { true }
    nonisolated override var acceptsFirstResponder: Bool { true }

    /// A right click here means "draw", never "show a menu".
    nonisolated override func menu(for event: NSEvent) -> NSMenu? { nil }

    func reset() {
        points = []
        isDrawing = false
        message = nil
        onLiveChange?([])
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0x35 { // kVK_Escape
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) { begin(event) }
    override func mouseDragged(with event: NSEvent) { extend(event) }
    override func mouseUp(with event: NSEvent) { finish() }

    override func rightMouseDown(with event: NSEvent) { begin(event) }
    override func rightMouseDragged(with event: NSEvent) { extend(event) }
    override func rightMouseUp(with event: NSEvent) { finish() }

    private func begin(_ event: NSEvent) {
        points = [convert(event.locationInWindow, from: nil)]
        isDrawing = true
        message = nil
        needsDisplay = true
    }

    private func extend(_ event: NSEvent) {
        guard isDrawing else { return }
        points.append(convert(event.locationInWindow, from: nil))
        onLiveChange?(points)
        needsDisplay = true
    }

    private func finish() {
        guard isDrawing else { return }
        isDrawing = false
        onLiveChange?(points)
        onFinish?(points)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .embedded: drawEmbedded()
        case .fullScreen: drawFullScreen()
        }
    }

    private func drawEmbedded() {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()

        guard points.count > 1 else {
            drawHint(L10n.text(.canvasDrawHint), color: .tertiaryLabelColor)
            return
        }
        drawTrail(lineWidth: 3)
    }

    private func drawFullScreen() {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard points.count > 1 else {
            drawHint(
                L10n.text(.canvasFullScreenHint),
                color: .white.withAlphaComponent(0.9),
                size: 15
            )
            return
        }
        drawTrail(lineWidth: 5)
    }

    private func drawTrail(lineWidth: CGFloat) {
        let trail = NSBezierPath()
        trail.lineWidth = lineWidth
        trail.lineCapStyle = .round
        trail.lineJoinStyle = .round
        trail.move(to: points[0])
        for point in points.dropFirst() {
            trail.line(to: point)
        }
        NSColor.controlAccentColor.setStroke()
        trail.stroke()

        // Start marker: hollow circle, the same cue the gesture list uses.
        let start = points[0]
        let marker = NSBezierPath(
            ovalIn: NSRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)
        )
        NSColor.black.withAlphaComponent(0.5).setFill()
        marker.fill()
        NSColor.controlAccentColor.setStroke()
        marker.lineWidth = 2.5
        marker.stroke()
    }

    private func drawHint(_ text: String, color: NSColor, size: CGFloat = 11) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: style == .fullScreen ? .medium : .regular),
            .foregroundColor: color,
        ]
        let string = text as NSString
        let textSize = string.size(withAttributes: attributes)
        string.draw(
            at: CGPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2),
            withAttributes: attributes
        )

        guard let message, !message.isEmpty else { return }
        let messageAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.systemOrange,
        ]
        let messageString = message as NSString
        let messageSize = messageString.size(withAttributes: messageAttributes)
        messageString.draw(
            at: CGPoint(
                x: bounds.midX - messageSize.width / 2,
                y: bounds.midY + textSize.height
            ),
            withAttributes: messageAttributes
        )
    }
}

/// The sheet's embedded canvas.
struct StrokeCanvasField: NSViewRepresentable {
    let clearToken: Int
    let onFinish: ([CGPoint]) -> Void
    let onLiveChange: ([CGPoint]) -> Void

    func makeNSView(context: Context) -> StrokeCanvasNSView {
        let view = StrokeCanvasNSView()
        view.style = .embedded
        view.onFinish = onFinish
        view.onLiveChange = onLiveChange
        return view
    }

    func updateNSView(_ view: StrokeCanvasNSView, context: Context) {
        view.onFinish = onFinish
        view.onLiveChange = onLiveChange

        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            view.reset()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastClearToken = 0
    }
}

/// Draws a stored trajectory, in the orientation the user drew it.
///
/// Used by the gesture list and by the editor's two shape columns. The points come from
/// `WGStrokeStep.drawingOrderPoints`, which already flips the stored y axis, so this is a straight
/// scale-and-fit — no coordinate reasoning here, by design. The start of the stroke gets a hollow
/// circle, matching the start symbol the original UI draws.
struct StrokeShapeView: View {
    let points: [CGPoint]
    var lineWidth: CGFloat = 2.2
    /// Shown when there is no shape to draw.
    var placeholder: String = L10n.text(.canvasNoShape)

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let color = Color.accentColor

            guard points.count > 1 else {
                if let point = points.first {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                        with: .color(color)
                    )
                } else {
                    context.draw(
                        Text(placeholder).font(.caption).foregroundStyle(.tertiary),
                        at: CGPoint(x: size.width / 2, y: size.height / 2)
                    )
                }
                return
            }

            let placement = Self.placement(for: points, in: size)
            let mapped = points.map(placement.map)
            var path = Path()
            path.addLines(mapped)
            context.stroke(path, with: .color(color), style: stroke)

            if let first = mapped.first, let last = mapped.last {
                context.fill(
                    Path(ellipseIn: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6)),
                    with: .color(.white.opacity(0.9))
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6)),
                    with: .color(color),
                    lineWidth: 2
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)),
                    with: .color(color)
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// Scales the trajectory to fit `size`, preserving aspect ratio and leaving a small inset.
    static func placement(for points: [CGPoint], in size: CGSize) -> Placement {
        let inset: CGFloat = 7
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        let spanX = max(maxX - minX, 1)
        let spanY = max(maxY - minY, 1)
        let scale = min((size.width - inset * 2) / spanX, (size.height - inset * 2) / spanY)
        let drawn = CGSize(width: spanX * scale, height: spanY * scale)

        return Placement(
            scale: scale,
            offset: CGPoint(
                x: (size.width - drawn.width) / 2 - minX * scale,
                y: (size.height - drawn.height) / 2 - minY * scale
            )
        )
    }

    struct Placement {
        let scale: CGFloat
        let offset: CGPoint

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
        }
    }
}
