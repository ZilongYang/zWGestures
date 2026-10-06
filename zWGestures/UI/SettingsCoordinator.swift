import AppKit

/// Wires the testable `SettingsModel` up to the persisted configuration and the live engine.
///
/// This is the only place that knows how the three pieces fit together: the model holds the
/// working copy, `ConfigController` owns the files, and `EngineController` has to be told when the
/// gesture set changes. Keeping it here means the SwiftUI layer stays a pure renderer and the
/// editing rules live in `ZWGCore` where `swift test` can reach them.
@MainActor
final class SettingsCoordinator {
    /// One model for the window's whole lifetime: the SwiftUI layer binds to this instance, so it
    /// is updated in place rather than replaced.
    let model: SettingsModel
    /// The `prefs.json` half of the window.
    let preferences: PreferencesModel

    private let config: ConfigController
    private let engine: EngineController
    /// Whether the engine was running when the shape editor opened.
    private var engineWasRunningBeforeShapeEditing = false

    init(config: ConfigController, engine: EngineController) {
        self.config = config
        self.engine = engine
        self.model = SettingsModel(config: config.config)
        self.preferences = PreferencesModel(preferences: config.preferences)
    }

    /// Picks up a fresh configuration, e.g. after a legacy re-import from the menu bar.
    func reloadFromConfig() {
        model.load(config: config.config)
        preferences.load(preferences: config.preferences)
    }

    /// Suspends the gesture engine while the user draws a shape in the editor.
    ///
    /// Recording uses the right mouse button — the button the global event tap watches — so the tap
    /// has to be out of the way or the drawing would be interpreted as a gesture (and might run
    /// whatever command that gesture carries). `pause` genuinely tears the tap down rather than
    /// ignoring events, which is why this works at all.
    func beginShapeEditing() {
        engineWasRunningBeforeShapeEditing = engine.isRunning
        guard engine.isRunning else { return }
        engine.pause(reason: L10n.text(.engineEditingShape))
    }

    /// Restores the engine, but only if it was running before the editor opened: a user who had
    /// paused it deliberately must not have it switched back on behind their back.
    func endShapeEditing() {
        defer { engineWasRunningBeforeShapeEditing = false }
        guard engineWasRunningBeforeShapeEditing else { return }
        engine.resume()
    }

    /// Asks for a new name with the standard sheet-and-text-field, then applies it.
    ///
    /// The prompt lives here rather than in the SwiftUI view because the model rejects blank names
    /// (`renameIntent` returns `false`) and this is the code that has to react to that.
    func promptRename(intentAt index: Int, currentName: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text(.dialogRenameGestureTitle)
        alert.informativeText = L10n.text(.dialogRenameGestureMessage)
        alert.addButton(withTitle: L10n.text(.dialogRename))
        alert.addButton(withTitle: L10n.text(.dialogCancel))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = currentName
        field.placeholderString = L10n.text(.dialogGestureName)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue
        guard model.renameIntent(at: index, to: newName) else {
            // Blank or a stale index: say so instead of silently doing nothing.
            let failure = NSAlert()
            failure.messageText = L10n.text(.dialogNameEmpty)
            failure.informativeText = L10n.text(.dialogNameUnchanged)
            failure.addButton(withTitle: L10n.text(.menuOK))
            failure.runModal()
            return
        }
    }

    /// Writes whichever of the two files has pending edits, then makes both live immediately.
    ///
    /// The engine is only re-applied after the writes succeed: a failed save must not leave the
    /// running engine with settings that are not on disk.
    @discardableResult
    func save() -> Bool {
        let gestureEdits = model.isDirty
        let preferenceEdits = preferences.isDirty
        guard gestureEdits || preferenceEdits else { return true }

        if let problem = preferences.validationError {
            presentFailure(title: L10n.text(.dialogPreferencesInvalid), reason: problem, path: config.store.preferencesURL.path)
            return false
        }

        do {
            if gestureEdits {
                try config.store.saveConfig(model.editedConfig)
            }
            if preferenceEdits {
                try config.store.savePreferences(preferences.editedPreferences)
            }
        } catch {
            Log.config.error("设置界面保存失败：\(error.localizedDescription, privacy: .public)")
            presentFailure(
                title: L10n.text(.dialogSaveFailed),
                reason: error.localizedDescription,
                path: (gestureEdits ? config.store.configURL : config.store.preferencesURL).path
            )
            return false
        }

        if gestureEdits {
            config.adopt(config: model.editedConfig)
            model.markSaved()
        }
        if preferenceEdits {
            config.adopt(preferences: preferences.editedPreferences)
            preferences.markSaved()
        }

        // 语言可能刚被改过：界面文案是渲染时取的，得让窗口重新读一遍。
        reloadFromConfig()

        // 让运行中的引擎立刻用上新值：超时影响手感，外观影响轨迹，目标模式影响选哪套手势集。
        engine.apply(startDragTimeout: config.preferences.startDragTimeoutSeconds)
        engine.apply(overlayStyle: OverlayStyle(preferences: config.preferences))
        engine.apply(config: config.config, targetMode: config.preferences.targetMode)

        let gestureCount = model.totalIntentCount
        let timeout = config.preferences.startDragTimeout
        Log.config.notice("""
            设置界面已保存：手势 \(gestureCount, privacy: .public) 条，\
            起始超时 \(timeout, privacy: .public) ms
            """)
        return true
    }

    private func presentFailure(title: String, reason: String, path: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.alertStyle = .warning
        alert.informativeText = """
            \(reason)

            文件位置：
            \(path)

            磁盘上的文件没有被改动，可以修正后重试。
            """
        alert.addButton(withTitle: L10n.text(.menuOK))
        alert.runModal()
    }
}
