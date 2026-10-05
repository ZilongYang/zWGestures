import AppKit
import Foundation

/// Opens the web-search command's URL.
///
/// Matches the original's documented behaviour: if the text selected in the frontmost app is a web
/// address, open it directly; otherwise search for it.
///
/// 🔴 **How the selected text is obtained matters more than it looks.**
///
/// The first implementation snapshotted the whole general pasteboard, sent ⌘C, read the pasteboard
/// back and restored the snapshot. That is fine for a text clipboard and catastrophic for an image
/// one: `NSPasteboardItem.copy()` materialises *every* representation, so a copied screenshot
/// (TIFF + BMP + PSD + PNG ≈ 70 MB — exactly what was on the clipboard on 2026-10-06) blocked the
/// main thread for about a minute, twice (docs/ROADMAP.md §22, §23). It also meant our own
/// synthetic ⌘C landed in the emergency-stop key monitor.
///
/// Now the selection is read through the Accessibility API — a cheaper, bounded, background call
/// that answers the actual question — and the clipboard is only ever asked for its **string** type,
/// which does not touch image data. Nothing here writes to the pasteboard any more.
@MainActor
enum WebSearchRunner {
    static func open(template: String, targetPID: Int32?) {
        Task { @MainActor in
            let selection = await selectedText(targetPID: targetPID)
            guard let url = url(for: selection, template: template) else {
                Log.action.error("Web 搜索的 URL 模板无效：\(template, privacy: .public)")
                return
            }
            Log.action.notice("""
                Web 搜索打开：\(url.absoluteString, privacy: .public)（\
                \(selection == nil ? "没选中文字，按空查询" : "已取到选中文字", privacy: .public)）
                """)
            NSWorkspace.shared.open(url)
        }
    }

    /// The text to search for: the frontmost app's selection.
    ///
    /// Two ways to get it, cheapest and safest first:
    /// 1. the Accessibility API's `AXSelectedText`（后台、限时，完全不碰粘贴板）；
    /// 2. a clipboard fallback that sends ⌘C — **but only when the clipboard already contains
    ///    text**. That restriction is the whole point: it means the image clipboard that caused the
    ///    one-minute hangs is never read, never copied and never overwritten.
    static func selectedText(targetPID: Int32?) async -> String? {
        if let targetPID, let selected = await AXSelectionReader.selectedText(for: targetPID) {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return await clipboardSelection()
    }

    /// ⌘C-based fallback, safe for the clipboard.
    ///
    /// Snapshotting "the whole pasteboard" was the bug: `NSPasteboardItem.copy()` materialises every
    /// representation, so a copied screenshot (≈70 MB) took the main thread out for about a minute.
    /// Snapshot only the *string* type here, and skip the trick entirely when the clipboard holds
    /// anything else — a search gesture may clobber a text clipboard for 150 ms and put it back, but
    /// it must never destroy an image the user just copied.
    private static func clipboardSelection() async -> String? {
        let pasteboard = NSPasteboard.general
        guard (pasteboard.types ?? []).contains(.string),
              let previous = pasteboard.string(forType: .string)
        else { return nil }

        let baseline = pasteboard.changeCount
        KeyEventPoster.postCopyShortcut()
        try? await Task.sleep(for: .milliseconds(150))

        let copied = pasteboard.string(forType: .string)
        if pasteboard.changeCount != baseline || copied != previous {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    static func url(for selection: String?, template: String) -> URL? {
        if let selection, !selection.isEmpty, looksLikeURL(selection) {
            return URL(string: selection)
        }
        let query = selection ?? ""
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let filled = template.replacingOccurrences(of: "{0}", with: encoded)
        return URL(string: filled)
    }

    static func looksLikeURL(_ text: String) -> Bool {
        guard !text.contains(" "), text.contains(".") || text.contains("://") else { return false }
        if text.contains("://") { return URL(string: text)?.scheme != nil }
        // `example.com/path` has no scheme; treat it as a URL only when it has a plausible host.
        guard let host = text.split(separator: "/").first, host.contains(".") else { return false }
        let parts = host.split(separator: ".")
        return parts.allSatisfy { !$0.isEmpty }
            && parts.last.map { $0.count >= 2 && $0.allSatisfy(\.isLetter) } == true
    }
}

/// Reads the focused app's selected text through the Accessibility API.
///
/// 🔴 The numbers here are limits, not suggestions. The AX API is a cross-process call, so it runs
/// on a background task and gets an explicit messaging timeout — the system default is 6 seconds
/// and a busy target application can be far worse. Same reasoning as
/// `ActionContextProvider.windowTitle`.
enum AXSelectionReader {
    static let timeout: Float = 0.25

    static func selectedText(for pid: Int32, timeout: Float = timeout) async -> String? {
        await Task.detached(priority: .userInitiated) {
            read(pid: pid, timeout: timeout)
        }.value
    }

    private static func read(pid: Int32, timeout: Float) -> String? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else { return nil }

        let focused = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, timeout)

        var selectionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectionValue
        ) == .success else { return nil }
        return selectionValue as? String
    }
}
