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
