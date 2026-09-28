import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Owns the settings window.
///
/// Everything that needs a modal (`NSAlert`) lives here rather than in `SettingsPanel`: the panel
/// stays a synchronous renderer of `SettingsModel`, which keeps it reviewable and keeps the
/// editing rules in the testable model.
@MainActor
final class SettingsWindowController {
    private let coordinator: SettingsCoordinator
    private var window: NSWindow?
    /// The gesture editor currently presented as a sheet.
    private var commandSheet: NSWindow?
    /// The editor's model, so the full-screen recorder can feed a shape back into it.
    private var gestureEditor: GestureEditorModel?
    /// The full-screen shape recorder, alive only while recording.
    private var shapeRecorder: StrokeRecordingOverlay?

    init(coordinator: SettingsCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        // Configuration can change behind our back (a menu-bar re-import), so re-read it whenever
        // the window comes up instead of holding a stale copy.
        coordinator.reloadFromConfig()

        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "zWGestures 设置（构建 \(BuildInfo.buildStamp)）"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: makePanel())
        window.center()
        return window
    }

    private func makePanel() -> SettingsPanel {
        SettingsPanel(
            model: coordinator.model,
            preferences: coordinator.preferences,
            onEdit: { [weak self] index, name in
                self?.coordinator.promptRename(intentAt: index, currentName: name)
            },
            onDelete: { [weak self] index, name in
                self?.confirmDelete(intentAt: index, name: name)
            },
            onSave: { [weak self] in
                // A successful save re-applies the configuration to the running engine, so the
                // change takes effect without a restart. The panel flashes「已保存」on `true`.
                self?.coordinator.save() ?? false
            },
            onRevert: {},
            onEditGesture: { [weak self] index, name in
                self?.presentGestureEditor(forExistingGestureAt: index, name: name)
            },
            onNewGesture: { [weak self] in
                self?.presentGestureEditorForNewGesture()
            },
            onMoveGesture: { [weak self] index, offset in
                self?.coordinator.model.moveIntent(at: index, by: offset)
            },
            onMoveGestureTo: { [weak self] from, to in
                self?.coordinator.model.moveIntent(from: from, to: to)
            },
            onSetEnabled: { [weak self] index, enabled in
                self?.coordinator.model.setEnabled(at: index, to: enabled)
            },
            onAddAppTarget: { [weak self] chooseFile in
                self?.presentAddAppTarget(chooseFile: chooseFile)
            },
            onRemoveTarget: { [weak self] selection in
                self?.confirmRemoveTarget(selection)
            },
            onDirtyChange: { [weak self] isDirty in
                // The standard macOS cue: a dot in the close button while edits are pending.
                self?.window?.isDocumentEdited = isDirty
            }
        )
    }

    // MARK: - Gesture editor

    /// Presents the gesture editor as an AppKit sheet.
    ///
    /// `beginSheet` rather than SwiftUI's `.sheet`: everything modal that is known to work in this
    /// app goes through AppKit, and a sheet that silently fails to appear is indistinguishable from
    /// a click that did nothing.
    ///
    /// The gesture engine is paused for the whole session, because the editor records the shape by
    /// dragging the **right** mouse button — the very button the global event tap is watching. With
    /// the tap torn down the drawing goes to our canvas instead of being turned into a gesture (and
    /// possibly executing some other command).
    private func presentGestureEditor(forExistingGestureAt index: Int, name: String) {
        guard let model = coordinator.model.intent(at: index) else {
            Log.ui.error("打开手势编辑器失败：取不到第 \(index, privacy: .public) 条手势")
            return
        }
        presentGestureEditor(
            GestureEditorModel(
                mode: .existing(index: index),
                intent: model,
                siblings: coordinator.model.selectedTargetIntents
            ),
            existingIndex: index
        )
    }

    private func presentGestureEditorForNewGesture() {
        presentGestureEditor(
            GestureEditorModel(
                newGestureNamed: defaultNewGestureName(),
                siblings: coordinator.model.selectedTargetIntents
            ),
            existingIndex: nil
        )
    }

    /// 「新手势」/「新手势 2」/… so a list of new gestures stays readable.
    private func defaultNewGestureName() -> String {
        let existing = Set(coordinator.model.selectedTarget?.intents.map(\.name) ?? [])
        guard existing.contains("新手势") else { return "新手势" }
        for number in 2...999 where !existing.contains("新手势 \(number)") {
            return "新手势 \(number)"
        }
        return "新手势"
    }

    private func presentGestureEditor(_ editor: GestureEditorModel, existingIndex: Int?) {
        guard let window else {
            Log.ui.error("打开手势编辑器失败：设置窗口不存在")
            return
        }
        // Never silently refuse because a sheet reference is still around: an editor that never
        // actually appeared would otherwise block every later attempt.
        if let existing = commandSheet {
            window.endSheet(existing)
            commandSheet = nil
        }

        gestureEditor = editor
        let sheet = GestureEditorSheet(
            model: editor,
            onRecordOnScreen: { [weak self] in self?.recordShapeOnScreen() },
            onCancel: { [weak self] in self?.dismissGestureEditor() },
            onCommit: { [weak self] intent in
                guard let self else { return }
                let applied = self.coordinator.model.apply(intent: intent, at: existingIndex)
                let shape = intent.strokeStep?.directionDescription ?? "无"
                let outcome = existingIndex == nil ? "新增" : "修改"
                Log.ui.notice("""
                    手势编辑器已提交：\(outcome, privacy: .public)，形状「\(shape, privacy: .public)」，\
                    动作 \(intent.command.typeName, privacy: .public)，成功 \(applied, privacy: .public)
                    """)
                self.dismissGestureEditor()
            }
        )

        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = existingIndex == nil ? "新建手势" : "编辑手势"
        sheetWindow.contentView = NSHostingView(rootView: sheet)
        commandSheet = sheetWindow
        coordinator.beginShapeEditing()
        window.beginSheet(sheetWindow)
        // Logged so that "the click did nothing" can be told apart from "the sheet failed to
        // appear": if this line is missing, the click never reached the editor.
        let subject = existingIndex.map { "第 \($0) 条" } ?? "新建"
        Log.ui.notice("打开手势编辑器：\(subject, privacy: .public)")
    }

    private func dismissGestureEditor() {
        shapeRecorder?.end()
        shapeRecorder = nil
        gestureEditor = nil
        guard let window, let sheet = commandSheet else {
            coordinator.endShapeEditing()
            return
        }
        window.endSheet(sheet)
        commandSheet = nil
        coordinator.endShapeEditing()
    }

    /// Starts recording a shape on the whole screen.
    ///
    /// Recording is rejected while it would be confusing rather than silently doing something: the
    /// model refuses a stroke that is too short, and the overlay then says why and stays open.
    private func recordShapeOnScreen() {
        guard let editor = gestureEditor else { return }
        let recorder = shapeRecorder ?? StrokeRecordingOverlay()
        shapeRecorder = recorder
        recorder.begin(
            onDraw: { points in editor.recordStroke(screenPoints: points) },
            onCancel: { [weak self] in
                self?.shapeRecorder = nil
                Log.ui.notice("用户取消了全屏录制手势形状")
            }
        )
    }

    // MARK: - Application targets

    /// Opens the「添加应用手势集」sheet, or the file picker directly.
    private func presentAddAppTarget(chooseFile: Bool) {
        if chooseFile {
            chooseApplicationFile()
            return
        }
        guard let window, commandSheet == nil else { return }

        let sheet = AddAppTargetSheet(
            runningApps: runningAppCandidates(),
            onChooseFile: { [weak self] in
                self?.chooseApplicationFile()
            },
            onCancel: { [weak self] in self?.dismissGestureEditor() },
            onAdd: { [weak self] candidate in
                self?.addApplicationTarget(candidate)
            }
        )

        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "添加应用手势集"
        sheetWindow.contentView = NSHostingView(rootView: sheet)
        commandSheet = sheetWindow
        window.beginSheet(sheetWindow)
    }

    /// Running applications that could be given a gesture set.
    ///
    /// Only regular apps (ones with a real window and Dock presence) and only those with an identity
    /// the resolver could match — otherwise the list would be full of background agents that can
    /// never receive a gesture.
    private func runningAppCandidates() -> [WGAppCandidate] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var candidates: [WGAppCandidate] = []

        for application in NSWorkspace.shared.runningApplications {
            guard application.activationPolicy == .regular else { continue }
            let identifier = application.bundleIdentifier
            guard identifier != ownBundleIdentifier else { continue }
            let path = application.bundleURL?.path
            guard identifier != nil || path != nil else { continue }
            let key = identifier ?? path ?? ""
            guard seen.insert(key).inserted else { continue }
            candidates.append(WGAppCandidate(
                name: application.localizedName ?? application.bundleURL?.lastPathComponent ?? key,
                bundleId: identifier,
                path: path
            ))
        }
        return candidates.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func chooseApplicationFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择一个应用（.app），给它单独配一套手势"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle = Bundle(url: url)
        let name = (bundle?.localizedInfoDictionary?["CFBundleName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        addApplicationTarget(WGAppCandidate(
            name: name,
            bundleId: bundle?.bundleIdentifier,
            path: url.path
        ))
    }

    /// Adds the target and selects it, or explains why it could not be added.
    private func addApplicationTarget(_ candidate: WGAppCandidate) {
        switch coordinator.model.addApplicationTarget(candidate) {
        case .success(let selection):
            coordinator.model.selection = selection
            Log.ui.notice("""
                已添加应用手势集：\(candidate.name, privacy: .public) \
                (\(candidate.bundleId ?? candidate.path ?? "?", privacy: .public))
                """)
            dismissGestureEditor()
        case .failure(let problem):
            let alert = NSAlert()
            alert.messageText = "无法添加这个应用"
            alert.alertStyle = .warning
            alert.informativeText = problem.errorDescription ?? "未知原因"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private func confirmRemoveTarget(_ selection: SettingsModel.Selection) {
        guard coordinator.model.canRemoveTarget(selection),
              let target = coordinator.model.targets.first(where: { candidate in
                  switch selection {
                  case .general: candidate.kind == .general
                  case .app(let id): candidate.id == id
                  case .special(let id): candidate.id == id
                  case .group(let id): candidate.id == id
                  }
              })
        else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "移除手势集「\(target.displayName)」？"
        alert.alertStyle = .warning
        alert.informativeText = """
            这个手势集里的 \(target.intents.count) 条手势会一起移除。
            全局手势集不能移除（它是一切的后备）。

            移除只作用于编辑中的配置，点「保存」后才会写入 config.json；            写入前的旧版本会自动备份到 Backups 目录。
            """
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        coordinator.model.removeTarget(selection)
    }

    private func confirmDelete(intentAt index: Int, name: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "删除手势「\(name)」？"
        alert.alertStyle = .warning
        alert.informativeText = "删除先只作用于编辑中的配置，点击「保存」后才会写入 config.json。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Deliberately no engine.apply here: the running engine keeps the saved configuration
        // until the edit is saved, so what runs always matches what is on disk.
        coordinator.model.deleteIntent(at: index)
    }
}
