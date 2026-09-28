import AppKit

/// A borderless, transparent, full-screen surface for recording a gesture shape.
///
/// Recording on the whole screen (rather than in a small box in the sheet) is how the gesture is
/// actually drawn in daily use, so the recorded trajectory is the one the user will reproduce.
///
/// The window must be allowed to become key, or Escape would never reach the view; a borderless
/// `NSWindow` refuses key status by default.
@MainActor
final class StrokeRecordingOverlay {
    private var window: NSWindow?
    private var canvas: StrokeCanvasNSView?

    var isRecording: Bool { window != nil }

    /// - Parameter onDraw: receives the captured trajectory; returns a message to keep recording
    ///   (e.g. "画得太短了"), or `nil` to finish. The overlay closes itself only on `nil`.
    func begin(
        onDraw: @escaping ([CGPoint]) -> String?,
        onCancel: @escaping () -> Void
    ) {
        guard window == nil else { return }

        // One surface covering every display: the trajectory only needs its shape, and the recorder
        // normalises away position and scale.
        let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let window = OverlayWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let canvas = StrokeCanvasNSView(frame: frame)
        canvas.style = .fullScreen
        canvas.onCancel = { [weak self] in
            self?.end()
            onCancel()
        }
        canvas.onFinish = { [weak self] points in
            guard let self else { return }
            if let message = onDraw(points) {
                // Rejected (too short, usually): clear the trail, stay in recording mode, say why.
                self.canvas?.reset()
                self.canvas?.message = message
            } else {
                self.end()
            }
        }

        window.contentView = canvas
        self.window = window
        self.canvas = canvas
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        Log.ui.notice("开始全屏录制手势形状")
    }

    func end() {
        guard let window else { return }
        self.window = nil
        canvas = nil
        window.orderOut(nil)
        Log.ui.notice("结束全屏录制手势形状")
    }
}

/// Borderless windows refuse key status by default, which would swallow Escape.
private final class OverlayWindow: NSWindow {
    /// `nonisolated`: AppKit asks these while routing events, outside any actor context.
    nonisolated override var canBecomeKey: Bool { true }
    nonisolated override var canBecomeMain: Bool { false }
}
