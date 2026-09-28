import AppKit
import SwiftUI

/// The settings window (P6, first slice): pick a target, see its gestures, search them, rename or
/// delete one, then save.
///
/// The layout keeps the two facts that are easy to get wrong in front of the user: an application
/// target **replaces** the global gesture set rather than adding to it, and a gesture is a stroke
/// plus the 手势修饰键 that follow it.
///
/// Editing rules live in `SettingsModel` (`ZWGCore`) so `swift test` covers them; this file only
/// renders and routes actions.
struct SettingsPanel: View {
    @ObservedObject var model: SettingsModel
    /// The `prefs.json` half, shown when the 偏好设置 section is selected.
    @ObservedObject var preferences: PreferencesModel

    /// Which half of the window is on screen.
    ///
    /// Deliberately **not** called `Section`: that name belongs to SwiftUI's view, and shadowing it
    /// made `Section("手势集") { … }` in the sidebar fail to compile.
    @State private var section: Pane = .gestures

    enum Pane: String, CaseIterable, Identifiable {
        case gestures
        case preferences

        var id: String { rawValue }
        var title: String {
            switch self {
            case .gestures: "手势集"
            case .preferences: "偏好设置"
            }
        }
    }
    /// Opens the rename prompt for the gesture at that index.
    let onEdit: (Int, String) -> Void
    /// Confirms and performs deletion of the gesture at that index.
    let onDelete: (Int, String) -> Void
    /// Writes the working copy and makes it live.
    /// - Returns: `true` on success; the caller shows the failure alert.
    let onSave: () -> Bool
    let onRevert: () -> Void
    /// Asks the window controller to open the gesture editor for the gesture at that index.
    ///
    /// The editor is presented by AppKit (`beginSheet`) rather than SwiftUI's `.sheet`, because
    /// every modal that is known to work in this app is presented through AppKit.
    let onEditGesture: (Int, String) -> Void
    /// Asks for a brand-new gesture in the selected gesture set.
    let onNewGesture: () -> Void
    /// Moves a gesture within its set (-1 = earlier / higher priority).
    let onMoveGesture: (Int, Int) -> Void
    /// Moves a dragged gesture to an explicit destination index.
    let onMoveGestureTo: (Int, Int) -> Void
    /// Turns one gesture on or off.
    let onSetEnabled: (Int, Bool) -> Void
    /// Adds an application gesture set; `true` goes straight to the file picker.
    let onAddAppTarget: (Bool) -> Void
    /// Removes a whole gesture set.
    let onRemoveTarget: (SettingsModel.Selection) -> Void
    /// Copies the gesture at that index, placing the copy right after it.
    let onDuplicateGesture: (Int) -> Void
    /// Lets the window show the standard macOS "edited" dot in its close button.
    let onDirtyChange: (Bool) -> Void

    /// Total gestures in the selected set — the destination index for 「移到最后」.
    private var gestureCount: Int { model.selectedTarget?.intents.count ?? 0 }

    /// Dragging is only offered with an empty search box: a filtered list shows a subset of rows,
    /// so a drop position would not correspond to where the user sees the row land.
    /// Either half having pending edits means there is something to save.
    private var hasPendingEdits: Bool { model.isDirty || preferences.isDirty }

    private var canReorder: Bool { model.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The row being dragged, and the row it is currently hovering over.
    @State private var draggingRowId: Int?
    @State private var dropTargetRowId: Int?

    /// Briefly shows「已保存」after a successful write.
    ///
    /// Saving used to give no visible feedback beyond the button greying out, which is
    /// indistinguishable from "the click did nothing" — reported by the user. The reset is a
    /// `Task` with a sleep rather than a `Timer` on purpose (see the Timer/SIGBUS note in
    /// README).
    @State private var justSaved = false
    @State private var savedResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            detailArea
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 460)
        // 两半都要参与窗口标题栏上的「已修改」小圆点，否则只改偏好时看不出来。
        .onChange(of: model.isDirty) { _, _ in
            onDirtyChange(hasPendingEdits)
        }
        .onChange(of: preferences.isDirty) { _, _ in
            onDirtyChange(hasPendingEdits)
        }
    }

    private func save() {
        guard onSave() else { return } // the failure alert comes from the coordinator
        justSaved = true
        savedResetTask?.cancel()
        savedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            justSaved = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("zWGestures 设置")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: $section) {
                ForEach(Pane.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            Spacer()
            if hasPendingEdits {
                Label("有未保存的改动", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if justSaved {
                Label("已保存到 config.json", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        switch section {
        case .gestures:
            return "共 \(model.targets.count) 个手势集 / \(model.totalIntentCount) 条手势"
        case .preferences:
            return "起始超时、轨迹外观、按哪个窗口选手势集"
        }
    }

    /// The half of the window the section picker selects.
    ///
    /// A separate property rather than an inline `switch` in `body`: the builder there already has
    /// several statements and refuses a `switch` among them.
    @ViewBuilder
    private var detailArea: some View {
        switch section {
        case .gestures:
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
                gestureList
                    .frame(minWidth: 460)
            }
        case .preferences:
            PreferencesPane(model: preferences)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                Section("手势集") {
                    ForEach(model.targets) { target in
                        sidebarRow(target)
                            .tag(selection(for: target))
                            .contextMenu {
                                Button("移除此手势集…") {
                                    onRemoveTarget(selection(for: target))
                                }
                                .disabled(!model.canRemoveTarget(selection(for: target)))
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 2) {
                Menu {
                    Button("从正在运行的应用添加…") { onAddAppTarget(false) }
                    Button("选择应用文件…") { onAddAppTarget(true) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
                .help("给某个应用单独配一套手势")

                Button {
                    onRemoveTarget(model.selection)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canRemoveTarget(model.selection))
                .help("移除选中的手势集（全局手势集不能移除）")

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
    }

    private func sidebarRow(_ target: WGTarget) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(for: target))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.displayName)
                if let caption = caption(for: target) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text("\(target.intents.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Adds a gesture to the selected set. Disabled when no set is selected.
    private var addGestureButton: some View {
        Button {
            onNewGesture()
        } label: {
            Label("新建手势", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .disabled(!model.hasValidSelection)
        .help("在当前手势集里新增一条手势：先画形状，再选动作")
    }

    private func symbol(for target: WGTarget) -> String {
        switch target.kind {
        case .general: "globe"
        case .app: "app"
        case .desktop: "menubar.dock.rectangle"
        case .other: "square.stack.3d.up"
        }
    }

    private func caption(for target: WGTarget) -> String? {
        switch target.kind {
        case .general:
            "默认手势集"
        case .app:
            // The replacement semantics the user confirmed against the original UI.
            "替换全局手势"
        case .desktop:
            "桌面"
        case .other:
            "分组"
        }
    }

    /// `List` selection needs a tag for every row, including targets the model cannot resolve.
    private func selection(for target: WGTarget) -> SettingsModel.Selection {
        switch target.kind {
        case .general: .general
        case .app: .app(id: target.id)
        case .desktop: .special(id: target.id)
        case .other: .group(id: target.id)
        }
    }

    // MARK: - Gesture list

    private var gestureList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "搜索手势名称、方向或命令",
                    text: Binding(
                        get: { model.query },
                        set: { model.setQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                if !model.query.isEmpty {
                    Button {
                        model.setQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                }
                Divider().frame(height: 16)
                addGestureButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if model.canToggleInheritance {
                HStack(spacing: 6) {
                    Toggle("继承全局手势", isOn: Binding(
                        get: { model.selectedTargetInheritsGlobal },
                        set: { model.setInheritsGlobal($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("""
                        打开：这个手势集自己的手势优先，没定义的继续用全局的（推荐）。\
                        关闭：这个应用只用手势集里的这几条，全局手势在这里全部失效。
                        """)
                    if model.inheritedRowCount > 0 {
                        Text("（下方 \(model.inheritedRowCount) 条灰色的是继承来的）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()

            if model.rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            GestureRowView(
                                row: row,
                                canReorder: canReorder,
                                isDropTarget: dropTargetRowId == row.id,
                                onToggleEnabled: { onSetEnabled(row.id, $0) },
                                onShowSource: { model.selection = .general },
                                onDuplicate: { onDuplicateGesture(row.id) },
                                onEdit: { onEdit(row.id, row.name) },
                                onDelete: { onDelete(row.id, row.name) },
                                onEditGesture: { onEditGesture(row.id, row.name) },
                                onMove: { offset in onMoveGesture(row.id, offset) },
                                canMoveEarlier: model.canMoveIntent(at: row.id, by: -1),
                                canMoveLater: model.canMoveIntent(at: row.id, by: 1),
                                onMoveToTop: { onMoveGestureTo(row.id, 0) },
                                onMoveToBottom: {
                                    onMoveGestureTo(row.id, max(gestureCount - 1, 0))
                                },
                                canMoveToTop: row.id > 0,
                                canMoveToBottom: row.id < gestureCount - 1,
                                onBeginDrag: { draggingRowId = row.id },
                                dragProvider: {
                                    NSItemProvider(object: String(row.id) as NSString)
                                },
                                onDrop: {
                                    // The dragged row's index is already in `draggingRowId`;
                                    // reading it back off the pasteboard would only add an async
                                    // hop (and a failure mode) for an in-process drag.
                                    let source = draggingRowId
                                    dropTargetRowId = nil
                                    draggingRowId = nil
                                    if let source, source != row.id {
                                        onMoveGestureTo(source, row.id)
                                    }
                                },
                                onHoverTarget: { isInside in
                                    dropTargetRowId = isInside ? row.id : nil
                                }
                            )
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: model.query.isEmpty ? "hand.point.up.left" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(emptyStateText)
                .foregroundStyle(.secondary)
            if !model.query.isEmpty, model.hiddenByFilterCount > 0 {
                Button("清除搜索") { model.setQuery("") }
                    .buttonStyle(.link)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateText: String {
        if !model.query.isEmpty {
            return "没有匹配的手势"
        }
        return model.hasValidSelection ? "这个手势集还没有手势" : "请先在左侧选择一个手势集"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSWorkspace.shared.open(ConfigStore.defaultDirectory)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("打开配置文件夹（里面有 Backups 子目录，保存前的旧版本都在那里）")
            Button("放弃改动") {
                model.revert()
                preferences.revert()
                onRevert()
            }
            .disabled(!hasPendingEdits)
            Button("保存") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasPendingEdits || (section == .gestures && !model.hasValidSelection))
                .help("写入 config.json / prefs.json，并让运行中的引擎立即生效")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footerText: String {
        var parts: [String] = []
        if let name = model.selectedTargetName {
            parts.append("当前：\(name)")
        }
        parts.append("显示 \(model.rows.count) 条")
        let hidden = model.hiddenByFilterCount
        if hidden > 0 {
            parts.append("被搜索隐藏 \(hidden) 条")
        }
        if model.inheritedRowCount > 0 {
            parts.append("继承全局 \(model.inheritedRowCount) 条")
        }
        if model.disabledCount > 0 {
            parts.append("其中已禁用 \(model.disabledCount) 条")
        }
        parts.append(canReorder ? "顺序＝优先级（靠前的优先），可拖拽调整" : "清空搜索后可拖拽调整顺序")
        parts.append("构建 \(BuildInfo.buildStamp)")
        parts.append("存于 \(ConfigStore.defaultDirectory.path)")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Row

/// One gesture: its trajectory, its name, the command it runs and its 手势修饰键.
private struct GestureRowView: View {
    let row: WGGestureRow
    let canReorder: Bool
    let isDropTarget: Bool
    /// Called with the new state when the row's checkbox is clicked.
    let onToggleEnabled: (Bool) -> Void
    /// Selects the general set, for a row inherited from it.
    let onShowSource: () -> Void
    /// Copies this gesture.
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onEditGesture: () -> Void
    let onMove: (Int) -> Void
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    /// 移到最前 / 移到最后：长列表里拖拽很难操作，需要一步到位的入口。
    let onMoveToTop: () -> Void
    let onMoveToBottom: () -> Void
    let canMoveToTop: Bool
    let canMoveToBottom: Bool
    /// Called when a drag of this row starts.
    let onBeginDrag: () -> Void
    /// The pasteboard item for this row's drag.
    let dragProvider: () -> NSItemProvider
    /// Called when the dragged row is dropped on this row.
    let onDrop: () -> Void
    /// Called as a drag enters/leaves this row, for the drop highlight.
    let onHoverTarget: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        // Double-click opens the editor (as asked), with two guaranteed fallbacks: the pencil
        // button on the right — an ordinary `Button`, the mechanism every working control in this
        // window uses — and the row's context menu.
        //
        // An earlier version made the whole row a Button, which reacted to a single click. That was
        // a workaround while the double-click was believed broken; it turned out the test had been
        // running an old binary all along, so the double-click gesture was never actually at fault.
        rowContent
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                // 继承行双击不改它，直接带到它真正所属的全局手势集。
                if row.isInherited { onShowSource() } else { onEditGesture() }
            }
            // Drag a row to change its priority: the list order is what decides which of two
            // gestures sharing a shape wins.
            .onDrag {
                guard !row.isInherited else { return NSItemProvider() }
                onBeginDrag()
                return dragProvider()
            }
            .onDrop(
                of: [.text],
                delegate: GestureRowDropDelegate(
                    isEnabled: canReorder && !row.isInherited,
                    onHover: onHoverTarget,
                    onDrop: onDrop
                )
            )
            .contextMenu {
                if row.isInherited {
                    // 继承来的手势属于全局，这里只能跳过去改，避免出现「改了却不是改这条」的错觉。
                    Button("跳到「全局」修改这条") { onShowSource() }
                } else {
                    Button("编辑手势…") { onEditGesture() }
                    Button("复制手势") { onDuplicate() }
                        .help("复制一份放在这条后面，再改形状或动作")
                    Divider()
                    if row.isEnabled {
                        Button("禁用这条手势") { onToggleEnabled(false) }
                    } else {
                        Button("启用这条手势") { onToggleEnabled(true) }
                    }
                    Divider()
                    // 顺序就是优先级：同形状的两条手势，靠前的生效。
                    Button("上移（优先级更高）") { onMove(-1) }
                        .disabled(!canMoveEarlier)
                    Button("下移（优先级更低）") { onMove(1) }
                        .disabled(!canMoveLater)
                    Button("移到最前（最高优先级）") { onMoveToTop() }
                        .disabled(!canMoveToTop)
                    Button("移到最后（最低优先级）") { onMoveToBottom() }
                        .disabled(!canMoveToBottom)
                    Divider()
                    Button("重命名…") { onEdit() }
                    Button("删除…", role: .destructive) { onDelete() }
                }
            }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            // A disabled gesture stays in the list with everything intact, it just never fires.
            // The switch is part of the row rather than a modal so toggling is one click.
            // An inherited row has no switch of its own: it belongs to the general set.
            if row.isInherited {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
            } else {
                Toggle("", isOn: Binding(
                    get: { row.isEnabled },
                    set: { onToggleEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(row.isEnabled ? "已启用：画这个形状会执行命令。点一下禁用它。" : "已禁用：画这个形状不会有任何反应。点一下启用。")
            }

            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(canReorder && !row.isInherited ? .tertiary : .quaternary)
                .help(canReorder
                    ? "按住拖动可以调整顺序；顺序靠前的优先（两条手势形状相同时由它决定谁生效）"
                    : "清空搜索后才能调整顺序")

            StrokeShapeView(points: row.points)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.body)
                        .lineLimit(1)
                    if let twin = row.collidingGestureName {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("形状与「\(twin)」相同：两条抢同一个输入，列表靠前的优先。想让你这条生效，右键 →「移到最前」或「上移」。")
                    }
                    if row.isInherited {
                        Button("继承自全局") { onShowSource() }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help("这条手势属于「全局」手势集，在这里只读。点一下跳到全局去修改。")
                    }
                    if row.executeOnRecognize {
                        Text("识别即执行")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                // 方向与手势修饰键都是「怎么触发」，必须挨在一起；右边那列只放「做什么」。
                HStack(spacing: 6) {
                    Text(row.direction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(row.modifiers, id: \.self) { modifier in
                        Text(modifier)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            Spacer(minLength: 8)

            Text(row.commandSummary)
                .font(.callout.monospaced())
                .lineLimit(1)

            // Always visible, and a real Button: this is the route that cannot fail.
            if !row.isInherited {
                Button(action: onEditGesture) {
                    Image(systemName: "pencil")
                        .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("编辑手势形状与动作（双击这一行也可以）")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .onHover { isHovering = $0 }
    }
}

/// Accepts a dropped row and reports the move.
private struct GestureRowDropDelegate: DropDelegate {
    let isEnabled: Bool
    let onHover: (Bool) -> Void
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        onHover(true)
    }

    func dropExited(info: DropInfo) {
        onHover(false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isEnabled ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        onHover(false)
        onDrop()
        return true
    }
}
