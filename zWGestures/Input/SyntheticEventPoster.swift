import CoreGraphics
import Foundation

/// Builds and posts synthetic pointer events.
///
/// Every synthetic event carries a magic value in `eventSourceUserData` so the event tap can
/// recognise and ignore its own output — otherwise replaying a click would immediately be
/// interpreted as a new trigger press and loop forever.
enum SyntheticEventPoster {
    /// "zWG" in ASCII, stored in the event's user-data field.
    static let userDataMagic: Int64 = 0x7A57_47

    /// Whether this event was produced by us rather than by real hardware.
    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == userDataMagic
    }

    /// Posts a sequence of synthetic events at the HID level.
    static func post(_ events: [PointerEvent]) {
        for pointerEvent in events {
            guard let cgEvent = makeCGEvent(pointerEvent) else {
                Log.input.error("无法构造合成事件：\(String(describing: pointerEvent.kind), privacy: .public)")
                continue
            }
            cgEvent.setIntegerValueField(.eventSourceUserData, value: userDataMagic)
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    /// Replays a completed gesture that was not recognised, so the app underneath still
    /// receives the press, the drag and the release.
    static func replay(_ candidate: GestureCandidate) {
        var events: [PointerEvent] = [
            PointerEvent(kind: .down(candidate.button), location: candidate.stroke.startPoint, timestamp: candidate.startedAt)
        ]
        for point in candidate.stroke.points.dropFirst() {
            events.append(PointerEvent(kind: .drag(candidate.button), location: point, timestamp: candidate.startedAt))
        }
        events.append(PointerEvent(kind: .up(candidate.button), location: candidate.stroke.endPoint, timestamp: candidate.endedAt))
        post(events)
    }

    static func makeCGEvent(_ event: PointerEvent) -> CGEvent? {
        switch event.kind {
        case .down(let button):
            return mouseEvent(button: button, type: mouseDownType(for: button), location: event.location)
        case .up(let button):
            return mouseEvent(button: button, type: mouseUpType(for: button), location: event.location)
        case .drag(let button):
            return mouseEvent(button: button, type: mouseDraggedType(for: button), location: event.location)
        case .move:
            return CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: event.location,
                mouseButton: .left
            )
        case .scroll(let deltaX, let deltaY):
            let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(deltaY.rounded()),
                wheel2: Int32(deltaX.rounded()),
                wheel3: 0
            )
            cgEvent?.location = event.location
            return cgEvent
        }
    }

    private static func mouseEvent(button: MouseButton, type: CGEventType, location: CGPoint) -> CGEvent? {
        let cgButton = CGMouseButton(rawValue: UInt32(button.rawValue)) ?? .left
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: cgButton
        )
        // `.otherMouse*` carries the actual button number in this field, and some apps only
        // look at the field rather than at the event type.
        event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        return event
    }

    private static func mouseDownType(for button: MouseButton) -> CGEventType {
        switch button {
        case .left: .leftMouseDown
        case .right: .rightMouseDown
        default: .otherMouseDown
        }
    }

    private static func mouseUpType(for button: MouseButton) -> CGEventType {
        switch button {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        default: .otherMouseUp
        }
    }

    private static func mouseDraggedType(for button: MouseButton) -> CGEventType {
        switch button {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        default: .otherMouseDragged
        }
    }
}
