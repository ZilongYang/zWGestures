import AppKit
import Foundation

/// Opens the web-search command's URL.
///
/// Matches the original's documented behaviour: if the text selected in the frontmost app is a
/// web address, open it directly; otherwise search for it. Selecting the text means sending ⌘C,
/// so the clipboard is snapshotted first and restored afterwards — a search gesture should not
/// quietly destroy whatever the user had copied.
@MainActor
enum WebSearchRunner {
    static func open(template: String) {
        let snapshot = PasteboardSnapshot.capture()
        copySelection()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let selected = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.restore()

            guard let url = url(for: selected, template: template) else {
                Log.action.error("Web 搜索的 URL 模板无效：\(template, privacy: .public)")
                return
            }
            Log.action.notice("Web 搜索打开：\(url.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(url)
        }
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

    private static func copySelection() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let commandKey: CGKeyCode = 0x37
        let cKey: CGKeyCode = 0x08
        for (code, down) in [(commandKey, true), (cKey, true), (cKey, false), (commandKey, false)] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = down && code == cKey ? .maskCommand : (down ? .maskCommand : [])
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventPoster.userDataMagic)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Snapshots and restores the general pasteboard.
private struct PasteboardSnapshot {
    let items: [NSPasteboardItem]?

    @MainActor
    static func capture() -> PasteboardSnapshot {
        let items = NSPasteboard.general.pasteboardItems?.compactMap { $0.copy() as? NSPasteboardItem }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func restore() {
        guard let items, !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
