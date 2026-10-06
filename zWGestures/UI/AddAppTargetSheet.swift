import AppKit
import SwiftUI

/// Picks an application to give its own gesture set.
///
/// Two routes, because they suit different situations: the list of running applications is quick
/// when the app is already open, and the file picker works for apps that are not running — and for
/// apps that never appear in the running list at all.
struct AddAppTargetSheet: View {
    let runningApps: [WGAppCandidate]
    let onChooseFile: () -> Void
    let onCancel: () -> Void
    let onAdd: (WGAppCandidate) -> Void

    @State private var query = ""
    @State private var selection: WGAppCandidate?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 460, height: 460)
    }

    private var filtered: [WGAppCandidate] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return runningApps }
        return runningApps.filter { candidate in
            let haystack = [candidate.name, candidate.bundleId ?? "", candidate.path ?? ""]
                .joined(separator: "\u{1}")
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.app")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(.addAppSheetTitle))
                    .font(.headline)
                Text(L10n.text(.addAppSheetSubtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.text(.addAppSheetSearchPlaceholder), text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var list: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "app.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(runningApps.isEmpty ? L10n.text(.addAppSheetNoRunning) : L10n.text(.addAppSheetNoMatches))
                        .foregroundStyle(.secondary)
                    Text(L10n.text(.addAppSheetHint))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.self) { candidate in
                            row(candidate)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private func row(_ candidate: WGAppCandidate) -> some View {
        // A plain click target rather than a List: this is a single-choice list, and a Button keeps
        // it consistent with the rest of this window's controls.
        Button {
            selection = candidate
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == candidate ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection == candidate ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.name)
                    if let identifier = candidate.bundleId {
                        Text(identifier)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(L10n.text(.addAppSheetChooseFile)) { onChooseFile() }
                .help(L10n.text(.addAppSheetChooseFileHelp))
            Spacer()
            Button(L10n.text(.dialogCancel), action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(L10n.text(.addAppSheetAdd)) {
                if let selection { onAdd(selection) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
