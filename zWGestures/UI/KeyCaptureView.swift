import AppKit
import SwiftUI

/// A focusable field that reports the key combination pressed instead of typing it.
///
/// Using a first-responder `NSView` rather than `NSEvent.addLocalMonitorForEvents` is deliberate:
/// a monitor's closure is not `@MainActor`-isolated, so touching the editor's state from it forces
/// `MainActor.assumeIsolated` — the exact combination that has already taken this app down once
/// (see the Timer/SIGBUS note in README). Key events delivered to a responder are already on the
/// main actor.
///
/// `performKeyEquivalent` is overridden because ⌘-combinations are otherwise consumed by the
/// window's menu before `keyDown` ever runs, and recording ⌘C is the single most common case.
final class KeyCaptureView: NSView {
    /// While `false` this view behaves like an ordinary (empty) view: every event is passed on, so
    /// Escape can still reach the sheet's Cancel button.
    var isRecording = false {
        didSet { if !isRecording { onModifiersChange?([]) } }
    }

    /// Called with one complete combination, e.g. `["Command", "ANSI_C"]`.
    var onStep: (([String]) -> Void)?
    /// Called when the held modifiers change, so the UI can show what is currently held.
    var onModifiersChange: (([String]) -> Void)?
    /// Called on Escape while recording.
    var onCancel: (() -> Void)?

    private static let escapeKeyCode: CGKeyCode = 0x35
    private static let modifierKeyCodeSet = Set(WGKeyCode.modifierKeyCodes.values)

    // See `TrailView.isFlipped`: these are queried from AppKit's responder machinery, so they stay
    // out of actor isolation.
    nonisolated override var acceptsFirstResponder: Bool { true }
    nonisolated override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == Self.escapeKeyCode {
            // Escape stops recording rather than being recorded as a step: it is the one key a
            // user reaches for to get out of a mode.
            onCancel?()
            return
        }
        guard let step = Self.step(for: event) else {
            NSSound.beep()
            return
        }
        onStep?(step)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == Self.escapeKeyCode {
            onCancel?()
            return true
        }
        guard event.type == .keyDown, let step = Self.step(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        onStep?(step)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        onModifiersChange?(Self.modifiers(for: event))
    }

    /// The `Key` names for one press: modifiers first, then the non-modifier key.
    ///
    /// Returns `nil` when the press carries no recordable key — a modifier pressed on its own only
    /// emits `flagsChanged`, so releasing ⌘ after ⌘C cannot record a second step made of just ⌘.
    static func step(for event: NSEvent) -> [String]? {
        guard !modifierKeyCodeSet.contains(event.keyCode),
              let name = WGKeyCode.name(forKeyCode: event.keyCode)
        else { return nil }
        return CommandEditorModel.normalized(modifiers(for: event) + [name])
    }

    /// Modifiers in the order macOS itself writes them: ⌃⌥⇧⌘.
    static func modifiers(for event: NSEvent) -> [String] {
        var names: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { names.append("Control") }
        if flags.contains(.option) { names.append("Option") }
        if flags.contains(.shift) { names.append("Shift") }
        if flags.contains(.command) { names.append("Command") }
        return names
    }
}

/// Bridges `KeyCaptureView` into SwiftUI and grabs first responder while recording.
struct KeyCaptureField: NSViewRepresentable {
    let isRecording: Bool
    let onStep: ([String]) -> Void
    let onModifiersChange: ([String]) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        apply(to: view)

        // Focus is handed over asynchronously: during `updateNSView` the view may not be in a
        // window yet, and a responder change made too early is silently dropped.
        //
        // A `Task` rather than `DispatchQueue.main.async` on purpose: a plain GCD block written in a
        // main-actor context inherits that isolation, which makes the compiler insert an
        // `assumeIsolated` check — the pattern that has crashed this app twice (see the Timer/SIGBUS
        // note in ROADMAP §8, and §23). `Task { @MainActor in }` hops properly instead.
        Task { @MainActor in
            guard let window = view.window else { return }
            if isRecording {
                guard window.firstResponder !== view else { return }
                window.makeFirstResponder(view)
            } else if window.firstResponder === view {
                // Give the keyboard back, so the sheet's Cancel shortcut works again.
                window.makeFirstResponder(nil)
            }
        }
    }

    private func apply(to view: KeyCaptureView) {
        view.isRecording = isRecording
        view.onStep = onStep
        view.onModifiersChange = onModifiersChange
        view.onCancel = onCancel
    }
}
