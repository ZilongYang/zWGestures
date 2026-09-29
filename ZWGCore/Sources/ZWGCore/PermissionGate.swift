import AppKit
import ApplicationServices
import Foundation
import os

/// Everything that touches macOS privacy permissions (TCC) lives here.
///
/// zWGestures needs:
/// - **Accessibility**: to install a `CGEventTap`, to read the frontmost window through the
///   Accessibility API, and to post synthetic key/mouse events.
/// - **Input Monitoring**: whether an additional grant is required on current macOS
///   releases is verified in P1 and documented here once known.
///
/// Automation (AppleEvents) permission is requested lazily by the system the first time a
/// `ShellScriptCommand` drives another app through AppleScript.
@MainActor
public enum PermissionGate {
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// `kAXTrustedCheckOptionPrompt` is exported as a mutable global `CFString` variable,
    /// which Swift 6 rejects as concurrency-unsafe shared mutable state. Its documented
    /// value is the string below, so the literal is used instead.
    private static let trustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

    /// Shows the system prompt that offers to open the Accessibility pane.
    /// - Returns: whether the process is already trusted.
    @discardableResult
    public static func requestAccessibility() -> Bool {
        let options = [trustedCheckOptionPromptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    public static func logCurrentState() {
        Log.app.notice("accessibility trusted: \(isAccessibilityTrusted, privacy: .public)")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// What the app should say about the Accessibility grant.
public enum AccessibilityGrantState: Equatable, Sendable {
    /// Granted — the input engine can run.
    case granted
    /// Never granted, as far as this install knows: the ordinary first-run path.
    case notGrantedYet
    /// This install has run with the grant before, so it was taken away.
    ///
    /// In practice that means an update. The released build is ad-hoc signed, and an ad-hoc
    /// designated requirement is derived from the CDHash — which changes on every compile — so TCC
    /// treats each version as a different application and drops the grant.
    case lostAfterUpdate
}

public enum AccessibilityGrantAssessment {
    /// Classifies the current state.
    ///
    /// Split out from `PermissionGate` so the distinction can be unit tested: "you have not granted
    /// this yet" and "an update broke it" need different explanations, and getting them the wrong way
    /// round tells the user to do the wrong thing.
    public static func assess(isTrusted: Bool, hasEverRunGranted: Bool) -> AccessibilityGrantState {
        if isTrusted { return .granted }
        return hasEverRunGranted ? .lostAfterUpdate : .notGrantedYet
    }
}
