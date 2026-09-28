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
                Text("添加应用手势集")
                    .font(.headline)
                Text("给某个应用单独配一套手势（会替换全局手势，不叠加）")
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
            TextField("搜索正在运行的应用", text: $query)
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
                    Text(runningApps.isEmpty ? "没有可添加的正在运行的应用" : "没有匹配的应用")
                        .foregroundStyle(.secondary)
                    Text("也可以直接用下面的「选择应用文件…」。")
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
            Button("选择应用文件…") { onChooseFile() }
                .help("适合没有运行、或不在上面列表里的应用")
            Spacer()
            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("添加") {
                if let selection { onAdd(selection) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
