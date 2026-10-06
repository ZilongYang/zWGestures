import Foundation

/// 用户选择的界面语言。`system` 表示跟随系统。
public enum WGLanguagePreference: String, Sendable, CaseIterable, Codable {
    case system
    case zhHans = "zh-Hans"
    case en

    /// 这条偏好在界面上的名字。语言选项一律用**该语言自己的写法**（简体中文 / English），
    /// 与系统设置里的做法一致 —— 一个看不懂中文的人不该在语言菜单里看到「简体中文」。
    public var localizedName: String {
        switch self {
        case .system: L10n.text(.languageSystem)
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }

    /// 实际要用的语言：偏好优先，其次系统首选语言；只在首选语言以 `zh` 开头时才用中文，
    /// 其余一律英文（这是这个特性的目的：世界上大多数人看到的应该是英文）。
    public static func resolve(
        preference: WGLanguagePreference,
        system: [String] = Locale.preferredLanguages
    ) -> WGLanguage {
        switch preference {
        case .zhHans: .zhHans
        case .en: .en
        case .system:
            system.first?.lowercased().hasPrefix("zh") == true ? .zhHans : .en
        }
    }
}

/// 实际生效的界面语言。
public enum WGLanguage: String, Sendable, CaseIterable {
    case zhHans = "zh-Hans"
    case en
}

/// 界面文案。
///
/// 为什么是自建的一层，而不是 `String Catalog`（见 docs/PLAN-2026-10-06-i18n.md 第 2.1 节）：
/// ① 自建表能单测（漏翻、英文表里残留中文、占位符一致性），`.xcstrings` 只能肉眼；
/// ② 本机 Xcode 工具链出过两次插件级故障，能不加新构建环节就不加；
/// ③ 语言可以显式切换，两种都能立刻看到。
///
/// **对照表写成 `switch` 而不是字典**：漏一条就编译不过。这是这张表唯一防呆手段，
/// 也是它比资源文件可靠的地方。
public enum L10n {
    private static let lock = NSLock()
    /// 进程级当前语言。启动时由 App 按偏好设置写入；测试里默认 `zhHans`，
    /// 所以断言中文文案的那些测试不需要改。
    nonisolated(unsafe) private static var current: WGLanguage = .zhHans

    public static var language: WGLanguage {
        lock.withLock { current }
    }

    public static func setLanguage(_ language: WGLanguage) {
        lock.withLock { current = language }
    }

    /// 按当前语言取一条文案。
    public static func text(_ key: Key) -> String {
        text(key, language: language)
    }

    /// 取指定语言的文案。
    ///
    /// 这一版**不读全局状态**，测试要用另一种语言时必须走它：语言是进程级状态，而 Swift Testing
    /// 默认并行跑用例 —— 一边切语言一边断言中文，会随机把别的用例带崩（2026-10-06 真发生过：
    /// `StrokeDirectionTests` 读到 `Right→Down` 而它断言的是「右→下」）。
    public static func text(_ key: Key, language: WGLanguage) -> String {
        let pair = key.pair
        return language == .en ? pair.en : pair.zh
    }

    /// 带参数的文案（占位符两语言必须一致，`L10nTests` 会检查）。
    public static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// 取指定语言、带参数的文案（同样不读全局状态）。
    public static func format(_ key: Key, language: WGLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language), arguments: arguments)
    }

    /// 语言偏好设置项自身的名字。
    public enum Key: CaseIterable, Sendable {
        // MARK: 语言
        case languageSystem
        case languageSection
        case prefsLanguageHelp

        // MARK: 模型、导入器与校验提示
        case cmdKindKeySequence
        case cmdKindWebSearch
        case cmdKindShellScript
        case cmdKindSystemFunction
        case cmdUnknownTypeWarningFormat
        case cmdKeySequenceNeedsStep
        case cmdWebSearchEmptyURL
        case cmdWebSearchNeedsPlaceholder
        case cmdShellScriptEmpty
        case cmdSystemFunctionMissing
        case gestureNewName
        case engineEditingShape
        case gestureConflictFormat
        case gestureNoOriginalShape
        case gestureNothingDrawn
        case gestureNameEmpty
        case gestureShapeMissing
        case prefsErrorTimeoutFormat
        case prefsErrorLineWidthFormat
        case prefsErrorGesturePos
        case settingsDuplicateTargetFormat
        case settingsAppUnidentifiable
        case settingsAppNoName
        case settingsCopySuffixFormat
        case modifierScrollUp
        case modifierScrollDown
        case recorderNothingDrawn
        case recorderTooShortFormat
        case unknownApplication
        case plannerUnknownFunctionFormat
        case plannerUnsupportedCommandFormat
        case plannerUnrecognisedKeysFormat
        case storeNoConfig
        case importerNoDirectory
        case importerNoGesturesFormat
        case importerPrefsFailedFormat
        case importerNoPrefs
        case codecUnknownObjectsFormat
        case codecUnknownTopLevelFormat
        case triggerHorizontalScroll
        case triggerScroll
        case tapTimeoutGiveUpFormat
        case buildUnknown

        // MARK: 弹窗、应用目标与引擎提示
        case dialogRenameGestureTitle
        case dialogRenameGestureMessage
        case dialogRename
        case dialogCancel
        case dialogGestureName
        case dialogNameEmpty
        case dialogNameUnchanged
        case dialogPreferencesInvalid
        case dialogSaveFailed
        case dialogCannotAddApp
        case dialogUnknownReason
        case dialogRemoveTargetFormat
        case dialogRemove
        case dialogDeleteGestureFormat
        case dialogDeleteGestureMessage
        case dialogDelete
        case dialogChooseAppTitle
        case dialogChoose
        case dialogNewGestureNumberFormat
        case sheetNone
        case sheetAdded
        case sheetModified
        case addAppSheetTitle
        case addAppSheetSubtitle
        case addAppSheetSearchPlaceholder
        case addAppSheetNoRunning
        case addAppSheetNoMatches
        case addAppSheetHint
        case addAppSheetChooseFile
        case addAppSheetChooseFileHelp
        case addAppSheetAdd
        case canvasDrawHint
        case canvasFullScreenHint
        case canvasNoShape
        case executorNothingToRun
        case enginePermissionLost
        case enginePermissionMissing
        case engineTapInstallFailed
        case engineOpenSystemSettings
        case engineLater
        case engineAutoDisabled
        case engineStayDisabled
        case engineReEnable
        case configMenuImport
        case configMenuDefaultGestures
        case configMenuLoadDefaults
        case importSummaryReadOnly
        case importSummaryAllTypes
        case eventTapCreateFailed
        case eventTapRunLoopSourceFailed
        case loginItemSystemReportFormat
        case loginItemWriteFailedFormat
        case loginItemBootstrapFailedFormat
        case loginItemDeleteFailedFormat
        case loginItemNoOutput

        // MARK: 命令编辑器与手势编辑器
        case cmdViewUnknownTypeBanner
        case cmdViewUnknownTypeDetailFormat
        case cmdViewReplaceIt
        case cmdViewKindLabel
        case cmdViewNoKeysHint
        case cmdViewStepFormat
        case cmdViewRemoveStepHelp
        case cmdViewHoldingPrefix
        case cmdViewStopRecording
        case cmdViewRecordKeys
        case cmdViewReRecord
        case cmdViewRecordReplaceHelp
        case cmdViewAddStep
        case cmdViewAddStepHelp
        case cmdViewClear
        case cmdViewKeySequenceHelp
        case cmdViewSystemHotKey
        case cmdViewRecordingReplace
        case cmdViewRecordingAppend
        case cmdViewPlaceholderNote
        case cmdViewShellNote
        case cmdViewFunctionLabel
        case gestureSheetEditTitle
        case gestureSheetTriggerNote
        case gestureSheetShapeTitle
        case gestureSheetShapeDetail
        case gestureSheetUnsupportedTrigger
        case gestureSheetUnsupportedTriggerDetail
        case gestureSheetModifierNote
        case gestureSheetConflictBanner
        case gestureSheetModifiers
        case gestureSheetNoModifier
        case gestureSheetRemoveModifier
        case gestureSheetAddModifier
        case gestureSheetModifierHelp
        case gestureSheetCurrentShape
        case gestureSheetOriginalShapePlaceholder
        case gestureSheetNewShape
        case gestureSheetClickToDraw
        case gestureSheetDrawHelp
        case gestureSheetNameTitle
        case gestureSheetActionTitle
        case gestureSheetActionDetail
        case gestureSheetEnabledDetail
        case gestureSheetExecuteNow
        case gestureSheetExecuteNowDetail
        case gestureSheetReadyAdd
        case gestureSheetReadySave
        case gestureSheetDone
        case gestureSheetRedraw
        case gestureSheetRedrawHelp
        case gestureSheetKeepOld
        case gestureSheetKeepOldHelp

        // MARK: 手势名中文化
        case menuRenameEnglishNames
        case renameNamesOfferFormat
        case renameNamesOfferDetail
        case renameNamesOfferAccept
        case renameNamesOfferDecline
        case renameNamesDoneFormat
        case renameNamesDoneDetail
        case renameNamesNothingToDo
        case renameNamesNothingToDoDetail

        // MARK: 菜单栏
        case menuImportFromWGestures
        case menuOpenSettings
        case menuOpenQuickStart
        case menuShowDebugHUD
        case menuAbout
        case menuQuit
        case menuEngineRunning
        case menuEnginePause
        case menuEngineResume
        case menuEnginePausedByUser
        case menuEngineWaitingPermission
        case menuEnginePermissionLost
        case menuEngineNotRunning
        case menuEngineStatusFormat
        case menuLoginItemOnFormat
        case menuPermissionGranted
        case menuPermissionLost
        case menuPermissionMissing
        case menuCannotEnableLoginItem
        case menuCannotDisableLoginItem
        case menuLoginItemFailureHelpFormat
        case menuOK
        case aboutTagline
        case aboutArchitectureFormat
        case aboutPanicShortcutFormat

        // MARK: 配置状态（菜单栏与设置窗口共用）
        case statusNotImported
        case statusLoadedFormat
        case statusImportedFormat
        case statusSeededFormat
        case statusErrorFormat
        case statusNoConfigReason

        // MARK: 开机自启状态
        case loginItemOff
        case loginItemOn
        case loginItemPending
        case loginItemNotFound
        case loginItemUnknown
        case mechanismDisabled
        case mechanismLoginItem

        // MARK: 偏好设置
        case prefsStartDragTimeout
        case prefsTimeoutDetail
        case prefsTimeoutHelp
        case prefsMillisecondsFormat
        case prefsTrailSection
        case prefsTrailSectionDetail
        case prefsShowTrail
        case prefsShowGestureName
        case prefsTrailNormal
        case prefsTrailRecognized
        case prefsLabelNormal
        case prefsLabelExecuted
        case prefsTrailLineWidth
        case prefsGestureNamePosition
        case prefsGestureNamePositionHelp
        case prefsTargetModeSection
        case prefsTargetModeDetail
        case prefsTargetModeHelp
        case prefsNotImplementedHelp
        case prefsNotImplementedNote

        // MARK: 设置窗口（手势列表）
        case settingsTabTargets
        case settingsTabPreferences
        case settingsWindowTitle
        case settingsUnsaved
        case settingsSavedToFormat
        case settingsCountsFormat
        case settingsPreferencesSubtitle
        case settingsRemoveTarget
        case settingsAddRunningApp
        case settingsAddAppFile
        case settingsAddAppHelp
        case settingsRemoveTargetHelp
        case settingsNewGesture
        case settingsNewGestureHelp
        case settingsDefaultTarget
        case settingsReplacesGeneral
        case settingsDesktopTarget
        case settingsGroupsTarget
        case settingsSearchPlaceholder
        case settingsClearSearch
        case settingsShowUnsupported
        case settingsHiddenUnsupportedFormat
        case settingsInheritsGeneral
        case settingsInheritedNoteFormat
        case settingsNoMatches
        case settingsEmptyTarget
        case settingsPickTarget
        case settingsOpenConfigFolder
        case settingsOpenConfigFolderHelp
        case settingsDiscard
        case settingsSave
        case settingsSaveHelp
        case settingsCurrentFormat
        case settingsShownFormat
        case settingsHiddenBySearchFormat
        case settingsInheritedCountFormat
        case settingsDisabledCountFormat
        case settingsOrderNote
        case settingsOrderNeedsNoSearch
        case settingsBuildFormat
        case settingsStoredAtFormat
        case settingsJumpToGeneral
        case settingsEditGesture
        case settingsDuplicateGesture
        case settingsDuplicateGestureHelp
        case settingsDisableGesture
        case settingsEnableGesture
        case settingsMoveUp
        case settingsMoveDown
        case settingsMoveTop
        case settingsMoveBottom
        case settingsRename
        case settingsDelete
        case settingsEnabledHelp
        case settingsDisabledHelp
        case settingsDragOrderHelp
        case settingsTwinConflictFormat
        case settingsInheritedRow
        case settingsInheritedRowHelp
        case settingsRunOnRecognise
        case settingsEditRowHelp

        // MARK: 列表里显示的形状与命令（ZWGCore 展示层）
        case displayDirectionUp
        case displayDirectionDown
        case displayDirectionLeft
        case displayDirectionRight
        case displaySinglePoint
        case displayClosedLoop
        case displayNoStroke
        case displayUnnamed
        case displayGeneralTarget
        case displayScrollHorizontal
        case displayScrollVertical
        case displayUnknownStepFormat
        case displayMouseLeft
        case displayMouseRight
        case displayMouseCenter
        case displayMouseSide1
        case displayMouseSide2
        case displayScrollUpFormat
        case displayScrollDownFormat
        case displayScrollLeftFormat
        case displayScrollRightFormat
        case displayEmptyKeySequence
        case displayWebSearch
        case displayWebSearchHostFormat
        case displayShellScript
        case displayShellScriptFormat
        case displaySystemFunctionKeyFormat
        case displayUnsupportedCommandFormat
        case edgeTop
        case edgeBottom
        case edgeLeft
        case edgeRight
        case edgeTopLeft
        case edgeTopRight
        case edgeBottomLeft
        case edgeBottomRight
        case edgeUnknownFormat
        case systemFunctionBrightnessDown
        case systemFunctionBrightnessUp
        case systemFunctionPreviousTrack
        case systemFunctionPlayPause
        case systemFunctionNextTrack
        case systemFunctionMute
        case systemFunctionVolumeDown
        case systemFunctionVolumeUp
        case targetModeFocused
        case targetModeUnderCursor

        var pair: (zh: String, en: String) {
            switch self {
            // 语言
            case .languageSystem: ("跟随系统", "System")
            case .languageSection: ("界面语言", "Interface language")
            case .prefsLanguageHelp:
                (
                    "切换后菜单栏与设置窗口会立刻重建；选「跟随系统」时按系统的首选语言决定。",
                    "The menu bar and this window are rebuilt immediately. Choose System to follow your Mac’s preferred language."
                )

            // 模型、导入器与校验提示
            case .cmdKindKeySequence: ("按键序列", "Key sequence")
            case .cmdKindWebSearch: ("Web 搜索", "Web Search")
            case .cmdKindShellScript: ("Shell 脚本", "Shell script")
            case .cmdKindSystemFunction: ("系统功能键", "System function key")
            case .cmdUnknownTypeWarningFormat: ("这条命令的类型（%@）本版本不认识，直接保存会覆盖它。", "This command's type (%@) is not recognised by this build; saving would overwrite it.")
            case .cmdKeySequenceNeedsStep: ("按键序列至少需要一步（例如 ⌘+C）。", "A key sequence needs at least one step (for example ⌘+C).")
            case .cmdWebSearchEmptyURL: ("搜索地址不能为空。", "The search address cannot be empty.")
            case .cmdWebSearchNeedsPlaceholder: ("搜索地址里需要 {0} 占位符，它会被替换成搜索词。", "The address needs a {0} placeholder; it is replaced by the search terms.")
            case .cmdShellScriptEmpty: ("脚本不能为空。", "The script cannot be empty.")
            case .cmdSystemFunctionMissing: ("请选择一个系统功能键。", "Pick a system function key.")
            case .gestureNewName: ("新手势", "New gesture")
            case .engineEditingShape: ("正在编辑手势形状", "Editing the gesture shape")
            case .gestureConflictFormat: ("这个形状与「%@」相同（距离 %.3f），两条手势抢同一个输入。列表里靠前的一条优先：要让这一条生效，保存后用右键把它「上移」到「%@」前面；否则画这个形状只会触发「%@」。", "This shape matches “%@” (distance %.3f) and both compete for one input; the earlier entry wins. To make this one fire, save and move it above “%@”; otherwise the shape only triggers “%@”.")
            case .gestureNoOriginalShape: ("（这条手势原本没有形状）", "(this gesture had no shape)")
            case .gestureNothingDrawn: ("（还没画）", "(nothing drawn yet)")
            case .gestureNameEmpty: ("名字不能为空。", "The name cannot be empty.")
            case .gestureShapeMissing: ("还没有画出手势形状 —— 点右边的框，在全屏幕上画一个。", "No shape drawn yet — click the box on the right and draw one full-screen.")
            case .prefsErrorTimeoutFormat: ("起始超时需要在 %.0f–%.0f 毫秒之间。", "The start timeout must be between %.0f and %.0f ms.")
            case .prefsErrorLineWidthFormat: ("线宽需要在 %.1f–%.1f 之间。", "The line width must be between %.1f and %.1f.")
            case .prefsErrorGesturePos: ("手势名位置需要在 0–1 之间。", "The gesture name position must be between 0 and 1.")
            case .settingsDuplicateTargetFormat: ("「%@」已经有自己的手势集了 —— 同一个应用只能有一个目标，否则第二个永远不会被用到。", "“%@” already has its own gesture set — one application can only have one target, or the second one is never used.")
            case .settingsAppUnidentifiable: ("这个应用既没有 Bundle ID 也没有路径，无法识别。", "This application has neither a bundle identifier nor a path, so it cannot be identified.")
            case .settingsAppNoName: ("这个应用没有可用的名称。", "This application has no usable name.")
            case .settingsCopySuffixFormat: ("%@ 副本", "%@ copy")
            case .modifierScrollUp: ("向上滚动", "Scroll up")
            case .modifierScrollDown: ("向下滚动", "Scroll down")
            case .recorderNothingDrawn: ("没有画出手势。在画布上按住并拖动画一个形状。", "No gesture drawn. Press and drag on the canvas to draw a shape.")
            case .recorderTooShortFormat: ("画得太短了（%.0f 点，至少需要 %.0f 点）。画得长一点再试。", "Too short (%.0f points; at least %.0f needed). Draw a longer stroke and try again.")
            case .unknownApplication: ("未知应用", "Unknown application")
            case .plannerUnknownFunctionFormat: ("未知的系统功能键索引 %d", "Unknown system function key index %d")
            case .plannerUnsupportedCommandFormat: ("不支持的命令类型 %@", "Unsupported command type %@")
            case .plannerUnrecognisedKeysFormat: ("第 %d 步里有无法识别的键名：%@", "Step %d contains unrecognised key names: %@")
            case .storeNoConfig: ("尚未导入配置，当前使用空的默认配置", "No configuration imported; using an empty default")
            case .importerNoDirectory: ("没有找到 WGestures 的配置目录", "No WGestures configuration directory found")
            case .importerNoGesturesFormat: ("配置目录里没有 gestures.json：%@", "No gestures.json in the configuration directory: %@")
            case .importerPrefsFailedFormat: ("prefs.json 解析失败，将使用默认偏好：%@", "Could not parse prefs.json; falling back to default preferences: %@")
            case .importerNoPrefs: ("配置目录里没有 prefs.json，将使用默认偏好", "No prefs.json in the configuration directory; using default preferences")
            case .codecUnknownObjectsFormat: ("配置里有本版本不认识的对象类型，相关内容会被丢弃：%@", "The configuration contains object types this build does not recognise; those entries will be dropped: %@")
            case .codecUnknownTopLevelFormat: ("配置里有未识别的顶层字段：%@", "Unknown top-level fields in the configuration: %@")
            case .triggerHorizontalScroll: ("横向滚轮", "Horizontal scroll")
            case .triggerScroll: ("滚轮", "Scroll")
            case .tapTimeoutGiveUpFormat: ("事件拦截器连续超时 %d 次，已主动停用", "The event tap timed out %d times in a row and has disabled itself")
            case .buildUnknown: ("未知构建", "Unknown build")

            // 弹窗、应用目标与引擎提示
            case .dialogRenameGestureTitle: ("重命名手势", "Rename gesture")
            case .dialogRenameGestureMessage: ("只改名称，不会改动笔画与命令。", "Only the name changes; the stroke and command stay as they are.")
            case .dialogRename: ("重命名", "Rename")
            case .dialogCancel: ("取消", "Cancel")
            case .dialogGestureName: ("手势名称", "Gesture name")
            case .dialogNameEmpty: ("名称不能为空", "The name cannot be empty")
            case .dialogNameUnchanged: ("手势名称没有改动。", "The gesture name is unchanged.")
            case .dialogPreferencesInvalid: ("偏好设置有误", "Invalid preferences")
            case .dialogSaveFailed: ("配置保存失败", "Could not save the configuration")
            case .dialogCannotAddApp: ("无法添加这个应用", "Could not add this application")
            case .dialogUnknownReason: ("未知原因", "Unknown reason")
            case .dialogRemoveTargetFormat: ("移除手势集「%@」？", "Remove the gesture set “%@”?")
            case .dialogRemove: ("移除", "Remove")
            case .dialogDeleteGestureFormat: ("删除手势「%@」？", "Delete the gesture “%@”?")
            case .dialogDeleteGestureMessage: ("删除先只作用于编辑中的配置，点击「保存」后才会写入 config.json。", "Deleting only affects the configuration being edited; it is written to config.json when you click Save.")
            case .dialogDelete: ("删除", "Delete")
            case .dialogChooseAppTitle: ("选择一个应用（.app），给它单独配一套手势", "Pick an application (.app) to give it its own gesture set")
            case .dialogChoose: ("选择", "Choose")
            case .dialogNewGestureNumberFormat: ("新手势 %d", "New gesture %d")
            case .sheetNone: ("无", "None")
            case .sheetAdded: ("新增", "Added")
            case .sheetModified: ("修改", "Changed")
            case .addAppSheetTitle: ("添加应用手势集", "Add an application gesture set")
            case .addAppSheetSubtitle: ("给某个应用单独配一套手势（会替换全局手势，不叠加）", "Give one application its own gesture set (it replaces the general set rather than adding to it)")
            case .addAppSheetSearchPlaceholder: ("搜索正在运行的应用", "Search running applications")
            case .addAppSheetNoRunning: ("没有可添加的正在运行的应用", "No running applications to add")
            case .addAppSheetNoMatches: ("没有匹配的应用", "No matching applications")
            case .addAppSheetHint: ("也可以直接用下面的「选择应用文件…」。", "You can also use “Choose an application…” below.")
            case .addAppSheetChooseFile: ("选择应用文件…", "Choose an application…")
            case .addAppSheetChooseFileHelp: ("适合没有运行、或不在上面列表里的应用", "For applications that are not running, or not in the list above")
            case .addAppSheetAdd: ("添加", "Add")
            case .canvasDrawHint: ("在这里按住拖动画出手势（左右键都可以）", "Press and drag here to draw a gesture (either mouse button)")
            case .canvasFullScreenHint: ("在全屏幕上按住并拖动画出新手势（左右键都可以）· 按 Esc 取消", "Press and drag anywhere to draw a new gesture (either mouse button) · press Esc to cancel")
            case .canvasNoShape: ("（无形状）", "(no shape)")
            case .executorNothingToRun: ("没有可执行的动作", "Nothing to run")
            case .enginePermissionLost: ("辅助功能授权已失效，画手势不会有反应", "Accessibility permission was revoked, so gestures will not work")
            case .enginePermissionMissing: ("尚未获得辅助功能权限", "Accessibility permission has not been granted yet")
            case .engineTapInstallFailed: ("事件拦截器安装失败", "The event tap could not be installed")
            case .engineOpenSystemSettings: ("打开系统设置", "Open System Settings")
            case .engineLater: ("稍后", "Later")
            case .engineAutoDisabled: ("手势引擎已自动停用", "The gesture engine has disabled itself")
            case .engineStayDisabled: ("保持停用", "Keep it disabled")
            case .engineReEnable: ("重新启用", "Re-enable")
            case .configMenuImport: ("导入", "Import")
            case .configMenuDefaultGestures: ("默认手势", "Default gestures")
            case .configMenuLoadDefaults: ("载入内置默认手势", "Load the built-in default gestures")
            case .importSummaryReadOnly: ("zWGestures 只读取原版配置，不会修改它。", "zWGestures only reads the original's configuration; it never modifies it.")
            case .importSummaryAllTypes: ("所有对象类型都能识别，没有数据被丢弃。", "Every object type is recognised, so nothing was dropped.")
            case .eventTapCreateFailed: ("CGEvent.tapCreate 返回 nil（通常是没有辅助功能权限）", "CGEvent.tapCreate returned nil (usually a missing Accessibility permission)")
            case .eventTapRunLoopSourceFailed: ("CFMachPortCreateRunLoopSource 失败", "CFMachPortCreateRunLoopSource failed")
            case .loginItemSystemReportFormat: ("系统登录项报告 %@", "The system login item reports %@")
            case .loginItemWriteFailedFormat: ("写入 %@ 失败：%@", "Could not write %@: %@")
            case .loginItemBootstrapFailedFormat: ("launchctl bootstrap 失败：%@", "launchctl bootstrap failed: %@")
            case .loginItemDeleteFailedFormat: ("删除 %@ 失败：%@", "Could not delete %@: %@")
            case .loginItemNoOutput: ("（无输出）", "(no output)")

            // 命令编辑器与手势编辑器
            case .cmdViewUnknownTypeBanner: ("这条命令的类型本版本不认识", "This command's type is not recognised by this build")
            case .cmdViewUnknownTypeDetailFormat: ("配置里存的是「%@」。本版本只能编辑按键序列、Web 搜索、Shell 脚本和系统功能键，直接保存会把它替换掉。", "The configuration stores “%@”. This build can only edit key sequences, Web Search, shell scripts and system function keys, so saving would replace it.")
            case .cmdViewReplaceIt: ("我知道，要替换它", "I know, replace it")
            case .cmdViewKindLabel: ("命令类型", "Command type")
            case .cmdViewNoKeysHint: ("还没有按键。点「录制按键」后按下一个组合键（例如 ⌘C）。", "No keys yet. Click Record keys, then press a combination (for example ⌘C).")
            case .cmdViewStepFormat: ("第 %d 步", "Step %d")
            case .cmdViewRemoveStepHelp: ("删除这一步", "Remove this step")
            case .cmdViewHoldingPrefix: ("已按住 ", "Holding ")
            case .cmdViewStopRecording: ("结束录制", "Stop recording")
            case .cmdViewRecordKeys: ("录制按键", "Record keys")
            case .cmdViewReRecord: ("重新录制", "Record again")
            case .cmdViewRecordReplaceHelp: ("按下一个组合键，它会替换掉现在的整个序列", "Press a combination; it replaces the whole sequence")
            case .cmdViewAddStep: ("添加一步", "Add a step")
            case .cmdViewAddStepHelp: ("按下一个组合键，把它接到序列的最后（可连续添加多步）", "Press a combination to append it to the sequence (you can add several in a row)")
            case .cmdViewClear: ("清空", "Clear")
            case .cmdViewKeySequenceHelp: ("单个组合键就是一个步骤；需要多步序列（例如先 ⌘V 再 ↩）时用「添加一步」。", "One combination is one step; use Add a step for a multi-step sequence (⌘V then ↩).")
            case .cmdViewSystemHotKey: ("这是一个系统快捷键（发送前不激活目标应用）", "This is a system-wide hot key (the target application is not activated first)")
            case .cmdViewRecordingReplace: ("正在录制，按下的组合键会成为整个序列…", "Recording: the combination you press becomes the whole sequence…")
            case .cmdViewRecordingAppend: ("正在添加一步，按下的组合键会接到序列最后…", "Adding a step: the combination you press goes to the end of the sequence…")
            case .cmdViewPlaceholderNote: ("{0} 会被替换成搜索词。", "{0} is replaced by the search terms.")
            case .cmdViewShellNote: ("脚本在 /bin/sh 下执行，可用的环境变量见 README。", "The script runs under /bin/sh; see the README for the available environment variables.")
            case .cmdViewFunctionLabel: ("功能", "Function")
            case .gestureSheetEditTitle: ("编辑手势", "Edit gesture")
            case .gestureSheetTriggerNote: ("触发方式：鼠标右键（本版本只实现了右键手势）", "Trigger: right mouse button (this build only implements right-button gestures)")
            case .gestureSheetShapeTitle: ("1. 手势形状", "1. Gesture shape")
            case .gestureSheetShapeDetail: ("左边是现在的手势；点右边可以在全屏幕上画一个新手势", "The left shows the current shape; click the right one to draw a new shape full-screen")
            case .gestureSheetUnsupportedTrigger: ("这条手势的触发方式本版本还没实现", "This gesture's trigger is not implemented in this build")
            case .gestureSheetUnsupportedTriggerDetail: ("它用的是屏幕边角或滚轮触发，而这两种触发还没实现 —— 形状和动作都保存得住，但画它不会有任何反应。等实现之后它就能直接用。", "It uses an edge or scroll trigger, neither of which is implemented yet — the shape and action are preserved, but drawing it does nothing. It will simply start working once they are.")
            case .gestureSheetModifierNote: ("手势修饰键是画这个形状的同时额外做的动作：同一条轨迹可以用它区分多个命令（例如「拷贝」与「剪切」都是向上，按住左键触发的是「剪切」）。", "A gesture modifier is something you do while drawing the shape, which lets one trajectory carry several commands (for example Copy and Cut are both an upward stroke; holding the left button triggers Cut).")
            case .gestureSheetConflictBanner: ("这个形状与另一条手势相同", "This shape matches another gesture")
            case .gestureSheetModifiers: ("修饰键", "Modifiers")
            case .gestureSheetNoModifier: ("（无 —— 画出这个形状就触发）", "(none — drawing the shape triggers it)")
            case .gestureSheetRemoveModifier: ("移除这个修饰键", "Remove this modifier")
            case .gestureSheetAddModifier: ("添加修饰键", "Add a modifier")
            case .gestureSheetModifierHelp: ("按住的鼠标键或滚轮方向；列表里已有的会变灰", "A held mouse button or scroll direction; ones already used are greyed out")
            case .gestureSheetCurrentShape: ("现在的手势", "Current shape")
            case .gestureSheetOriginalShapePlaceholder: ("（原本没有形状）", "(no shape originally)")
            case .gestureSheetNewShape: ("新手势", "New shape")
            case .gestureSheetClickToDraw: ("点击这里在全屏幕上画一个", "Click here to draw one full-screen")
            case .gestureSheetDrawHelp: ("点一下，然后在屏幕任意位置按住拖动，画出新手势", "Click, then press and drag anywhere on screen to draw the new shape")
            case .gestureSheetNameTitle: ("2. 名称", "2. Name")
            case .gestureSheetActionTitle: ("3. 这个手势做什么", "3. What this gesture does")
            case .gestureSheetActionDetail: ("形状定下来之后，再选它要触发的动作", "Once the shape is settled, choose the action it should run")
            case .gestureSheetEnabledDetail: ("取消勾选后，这条手势会保留在列表里但不再生效（画这个形状不会有任何反应）。", "Unticked, the gesture stays in the list but never fires (drawing this shape does nothing).")
            case .gestureSheetExecuteNow: ("识别手势后立即执行", "Run as soon as the gesture is recognised")
            case .gestureSheetExecuteNowDetail: ("勾选后，笔画一被识别就执行命令，不再等待后面的手势修饰键；同一条轨迹用修饰键区分多个命令时不要勾选。", "Ticked, the command runs as soon as the stroke is recognised instead of waiting for gesture modifiers; leave it unticked when modifiers distinguish several commands on one trajectory.")
            case .gestureSheetReadyAdd: ("可以添加了", "Ready to add")
            case .gestureSheetReadySave: ("可以保存了", "Ready to save")
            case .gestureSheetDone: ("完成", "Done")
            case .gestureSheetRedraw: ("重画", "Redraw")
            case .gestureSheetRedrawHelp: ("丢掉刚画的形状，重新在全屏幕上画一个", "Discard the shape you just drew and draw another one full-screen")
            case .gestureSheetKeepOld: ("不改了", "Leave it")
            case .gestureSheetKeepOldHelp: ("放弃新手势，这条手势保持原来的形状", "Discard the new shape; this gesture keeps its original one")

            // 手势名中文化
            case .menuRenameEnglishNames: ("把英文手势名改为中文", "Rename English gestures to Chinese")
            case .renameNamesOfferFormat: ("检测到 %d 条手势用的是英文名（Close、Web Search 这类）", "%d gestures use English names (Close, Web Search and so on)")
            case .renameNamesOfferDetail: ("要用原版自带的那张中文译名表把它们逐条改成中文吗？改之前会自动备份到配置目录的 Backups 里；你自己起过名字的手势不会被动。", "Rename them using the original's own Chinese name table? The current configuration is backed up to the Backups folder first, and gestures you named yourself are never touched.")
            case .renameNamesOfferAccept: ("改成中文", "Rename them")
            case .renameNamesOfferDecline: ("不用了", "Not now")
            case .renameNamesDoneFormat: ("已把 %d 条手势名改成中文", "Renamed %d gestures to Chinese")
            case .renameNamesDoneDetail: ("改之前的配置已经备份到配置目录的 Backups 里，想回退随时可以拿。", "The previous configuration is in the Backups folder if you want to go back.")
            case .renameNamesNothingToDo: ("没有需要改名的英文手势名", "No English gesture names to rename")
            case .renameNamesNothingToDoDetail: ("配置里的手势名要么已经是中文，要么不在内置译名表里 —— 你自己起的名字一律不动。", "Every gesture name is either already Chinese or missing from the built-in name table — names you chose yourself are never touched.")

            // 菜单栏
            case .menuImportFromWGestures: ("从 WGestures 导入配置…", "Import from WGestures…")
            case .menuOpenSettings: ("打开设置…", "Open Settings…")
            case .menuOpenQuickStart: ("打开快速入门", "Open Quick Start")
            case .menuShowDebugHUD: ("显示调试面板", "Show Debug Panel")
            case .menuAbout: ("关于 zWGestures", "About zWGestures")
            case .menuQuit: ("退出 zWGestures", "Quit zWGestures")
            case .menuEngineRunning: ("手势引擎：运行中", "Gesture engine: running")
            case .menuEnginePause: ("暂停手势引擎", "Pause the gesture engine")
            case .menuEngineResume: ("继续手势引擎", "Resume the gesture engine")
            case .menuEnginePausedByUser: ("用户从菜单暂停", "Paused from the menu")
            case .menuEngineWaitingPermission:
                ("手势引擎：等待辅助功能授权", "Gesture engine: waiting for Accessibility permission")
            case .menuEnginePermissionLost:
                ("手势引擎：授权已失效（需重新授权）", "Gesture engine: permission revoked (re-authorise)")
            case .menuEngineNotRunning: ("手势引擎未运行", "Gesture engine is not running")
            case .menuEngineStatusFormat: ("手势引擎：%@", "Gesture engine: %@")
            case .menuLoginItemOnFormat: ("开机自动启动：已开启（%@）", "Launch at login: on (%@)")
            case .menuPermissionGranted: ("辅助功能权限：已授权", "Accessibility permission: granted")
            case .menuPermissionLost:
                ("辅助功能权限：已失效（点击重新授权）", "Accessibility permission: revoked (click to re-authorise)")
            case .menuPermissionMissing:
                ("辅助功能权限：未授权（点击前往授权）", "Accessibility permission: not granted (click to grant)")
            case .menuCannotEnableLoginItem: ("无法开启开机自启", "Could not turn on launch at login")
            case .menuCannotDisableLoginItem: ("无法关闭开机自启", "Could not turn off launch at login")
            case .menuLoginItemFailureHelpFormat:
                (
                    "当前应用路径：\n%@\n\n登录项记录的是应用路径，请把 zWGestures.app 放到一个固定的位置（例如 /Applications），再重试。",
                    "Current app location:\n%@\n\nThe login item stores the app path, so keep zWGestures.app in a fixed place (such as /Applications) and try again."
                )
            case .menuOK: ("好", "OK")
            case .aboutTagline:
                ("原生的 Apple Silicon 鼠标手势工具", "A native Apple Silicon mouse gesture tool")
            case .aboutArchitectureFormat: ("运行架构：%@", "Architecture: %@")
            case .aboutPanicShortcutFormat: ("急停快捷键：%@", "Emergency stop: %@")

            // 配置状态
            case .statusNotImported: ("尚未导入配置", "No configuration imported yet")
            case .statusLoadedFormat:
                ("配置已载入（%d 条手势）", "Configuration loaded (%d gestures)")
            case .statusImportedFormat:
                ("已从 WGestures %@ 导入 %d 条手势", "Imported from WGestures %@: %d gestures")
            case .statusSeededFormat:
                ("已载入内置默认手势（%d 条）", "Loaded the built-in default gestures (%d)")
            case .statusErrorFormat: ("配置出错：%@", "Configuration error: %@")
            case .statusNoConfigReason:
                ("既没有可用的配置，也没有内置默认手势包", "Neither a configuration nor the built-in default pack is available")

            // 开机自启
            case .loginItemOff: ("开机不自动启动", "Launch at login: off")
            case .loginItemOn: ("开机自动启动：已开启", "Launch at login: on")
            case .loginItemPending:
                ("开机自动启动：等待系统设置里确认", "Launch at login: waiting for approval in System Settings")
            case .loginItemNotFound:
                ("开机自动启动：系统找不到该应用", "Launch at login: the system cannot find this app")
            case .loginItemUnknown: ("开机自动启动：状态未知", "Launch at login: unknown state")
            case .mechanismDisabled: ("未启用", "not used")
            case .mechanismLoginItem: ("系统登录项", "system login item")

            // 偏好设置
            case .prefsStartDragTimeout: ("手势起始超时", "Start-drag timeout")
            case .prefsTimeoutDetail:
                ("按住触发键后多久之内开始移动才算画手势", "How soon movement must start for the press to count as a gesture")
            case .prefsTimeoutHelp:
                (
                    "超过这个时间还没有移动，就当作普通点击 —— 右键菜单照常弹出。数值大：更容易画出手势，但点菜单略慢；数值小：点菜单更快，但起手要更干脆。",
                    "Without movement inside this window the press is treated as an ordinary click, and the context menu opens as usual. Larger: gestures are easier to start, menus feel slower. Smaller: menus are snappier, but you must start moving sooner."
                )
            case .prefsMillisecondsFormat: ("%d 毫秒", "%d ms")
            case .prefsTrailSection: ("轨迹与手势名", "Trail & gesture name")
            case .prefsTrailSectionDetail: ("画手势时的屏幕提示", "What appears on screen while you draw")
            case .prefsShowTrail: ("显示轨迹", "Show the trail")
            case .prefsShowGestureName: ("显示手势名", "Show the gesture name")
            case .prefsTrailNormal: ("轨迹（未识别）", "Trail (not recognised)")
            case .prefsTrailRecognized: ("轨迹（已识别）", "Trail (recognised)")
            case .prefsLabelNormal: ("手势名（常态）", "Gesture name (idle)")
            case .prefsLabelExecuted: ("手势名（已执行）", "Gesture name (executed)")
            case .prefsTrailLineWidth: ("轨迹线宽", "Trail line width")
            case .prefsGestureNamePosition: ("手势名位置", "Gesture name position")
            case .prefsGestureNamePositionHelp:
                (
                    "手势名位置：0 在最上面，1 在最下面（按屏幕高度比例）。",
                    "0 places the name at the top of the screen, 1 at the bottom (a fraction of the screen height)."
                )
            case .prefsTargetModeSection: ("按哪个窗口选手势集", "Which window picks the gesture set")
            case .prefsTargetModeDetail:
                ("决定「按应用切换手势集」用哪个应用", "Which application decides the per-app gesture set")
            case .prefsTargetModeHelp:
                (
                    "应用目标会替换全局手势集，不叠加 —— 例如给 Finder 配了手势集，在 Finder 里就只用 Finder 那一套。",
                    "An application target replaces the general gesture set rather than adding to it: with a set configured for Finder, only that set applies while Finder is frontmost."
                )
            case .prefsNotImplementedNote:
                ("原版里还有两项本版本没有实现", "Two options from the original are not implemented yet")
            case .prefsNotImplementedHelp:
                (
                    "「显示起始超时指示器」和「显示状态图标」在代码里都还没有被使用，所以这里不提供开关 —— 提供了也是点了没反应。（状态图标尤其要谨慎：本应用只有菜单栏图标一个入口，隐藏了就回不来。）",
                    "This build never reads the start-drag timeout indicator or the status icon, so there are no switches for them — a switch that does nothing is worse than none. (Hiding the status icon would be especially dangerous: the menu-bar item is this app’s only way in.)"
                )

            // 设置窗口（手势列表）
            case .settingsTabTargets: ("手势集", "Gesture sets")
            case .settingsTabPreferences: ("偏好设置", "Preferences")
            case .settingsWindowTitle: ("zWGestures 设置", "zWGestures Settings")
            case .settingsUnsaved: ("有未保存的改动", "Unsaved changes")
            case .settingsSavedToFormat: ("已保存到 %@", "Saved to %@")
            case .settingsCountsFormat: ("%d 个手势集 / %d 条手势", "%d gesture sets / %d gestures")
            case .settingsPreferencesSubtitle: ("起始超时、轨迹外观、按哪个窗口选手势集", "Start timeout, trail appearance, and which window picks the gesture set")
            case .settingsRemoveTarget: ("移除此手势集…", "Remove this gesture set…")
            case .settingsAddRunningApp: ("从正在运行的应用添加…", "Add from running applications…")
            case .settingsAddAppFile: ("选择应用文件…", "Choose an application…")
            case .settingsAddAppHelp: ("给某个应用单独配一套手势", "Give one application its own gesture set")
            case .settingsRemoveTargetHelp: ("移除选中的手势集（全局手势集不能移除）", "Remove the selected gesture set (the general set cannot be removed)")
            case .settingsNewGesture: ("新建手势", "New gesture")
            case .settingsNewGestureHelp: ("在当前手势集里新增一条手势：先画形状，再选动作", "Add a gesture to the current set: draw its shape first, then pick an action")
            case .settingsDefaultTarget: ("默认手势集", "Default gesture set")
            case .settingsReplacesGeneral: ("替换全局手势", "Replaces the general gesture set")
            case .settingsDesktopTarget: ("桌面", "Desktop")
            case .settingsGroupsTarget: ("分组", "Groups")
            case .settingsSearchPlaceholder: ("搜索手势名称、方向或命令", "Search name, direction or command")
            case .settingsClearSearch: ("清除搜索", "Clear search")
            case .settingsShowUnsupported: ("显示本版本暂不支持的手势", "Show gestures this build cannot trigger")
            case .settingsHiddenUnsupportedFormat: ("（当前隐藏 %d 条：边角 / 滚轮触发）", "(%d hidden: edge / scroll triggers)")
            case .settingsInheritsGeneral: ("继承全局手势", "Inherit general gestures")
            case .settingsInheritedNoteFormat: ("（下方 %d 条灰色的是继承来的）", "(%d grey rows below are inherited)")
            case .settingsNoMatches: ("没有匹配的手势", "No matching gestures")
            case .settingsEmptyTarget: ("这个手势集还没有手势", "This gesture set has no gestures yet")
            case .settingsPickTarget: ("请先在左侧选择一个手势集", "Pick a gesture set on the left first")
            case .settingsOpenConfigFolder: ("打开配置文件夹", "Open the configuration folder")
            case .settingsOpenConfigFolderHelp: ("里面有 Backups 子目录，保存前的旧版本都在那里", "It contains a Backups folder with previous versions")
            case .settingsDiscard: ("放弃改动", "Discard changes")
            case .settingsSave: ("保存", "Save")
            case .settingsSaveHelp: ("写入 config.json / prefs.json，并让运行中的引擎立即生效", "Write config.json / prefs.json and apply them to the running engine immediately")
            case .settingsCurrentFormat: ("当前：%@", "Current: %@")
            case .settingsShownFormat: ("显示 %d 条", "%d shown")
            case .settingsHiddenBySearchFormat: ("被搜索隐藏 %d 条", "%d hidden by search")
            case .settingsInheritedCountFormat: ("继承全局 %d 条", "%d inherited")
            case .settingsDisabledCountFormat: ("其中已禁用 %d 条", "%d disabled")
            case .settingsOrderNote: ("顺序＝优先级（靠前的优先），可拖拽调整", "Order is priority (the earlier one wins); drag to rearrange")
            case .settingsOrderNeedsNoSearch: ("清空搜索后可拖拽调整顺序", "Clear the search to rearrange by dragging")
            case .settingsBuildFormat: ("构建 %@", "Build %@")
            case .settingsStoredAtFormat: ("存于 %@", "Stored at %@")
            case .settingsJumpToGeneral: ("跳到「全局」修改这条", "Jump to General to edit this one")
            case .settingsEditGesture: ("编辑手势…", "Edit gesture…")
            case .settingsDuplicateGesture: ("复制手势", "Duplicate gesture")
            case .settingsDuplicateGestureHelp: ("复制一份放在这条后面，再改形状或动作", "Add a copy right after this one, then change its shape or action")
            case .settingsDisableGesture: ("禁用这条手势", "Disable this gesture")
            case .settingsEnableGesture: ("启用这条手势", "Enable this gesture")
            case .settingsMoveUp: ("上移（优先级更高）", "Move up (higher priority)")
            case .settingsMoveDown: ("下移（优先级更低）", "Move down (lower priority)")
            case .settingsMoveTop: ("移到最前（最高优先级）", "Move to top (highest priority)")
            case .settingsMoveBottom: ("移到最后（最低优先级）", "Move to bottom (lowest priority)")
            case .settingsRename: ("重命名…", "Rename…")
            case .settingsDelete: ("删除…", "Delete…")
            case .settingsEnabledHelp: ("已启用：画这个形状会执行命令。点一下禁用它。", "Enabled: drawing this shape runs the command. Click to disable.")
            case .settingsDisabledHelp: ("已禁用：画这个形状不会有任何反应。点一下启用。", "Disabled: drawing this shape does nothing. Click to enable.")
            case .settingsDragOrderHelp: ("按住拖动可以调整顺序；顺序靠前的优先（两条手势形状相同时由它决定谁生效）", "Drag to rearrange. The earlier entry wins, which is what decides between two gestures with the same shape.")
            case .settingsTwinConflictFormat: ("形状与「%@」相同：两条抢同一个输入，列表靠前的优先。想让你这条生效，右键 →「移到最前」或「上移」。", "Same shape as “%@”: both compete for one input and the earlier entry wins. To make this one fire, right-click → Move to top or Move up.")
            case .settingsInheritedRow: ("继承自全局", "Inherited from General")
            case .settingsInheritedRowHelp: ("这条手势属于「全局」手势集，在这里只读。点一下跳到全局去修改。", "This gesture belongs to the General set and is read-only here. Click to jump there and edit it.")
            case .settingsRunOnRecognise: ("识别即执行", "Run when recognised")
            case .settingsEditRowHelp: ("编辑手势形状与动作（双击这一行也可以）", "Edit the shape and action (double-clicking the row works too)")

            // 展示层
            case .displayDirectionUp: ("上", "Up")
            case .displayDirectionDown: ("下", "Down")
            case .displayDirectionLeft: ("左", "Left")
            case .displayDirectionRight: ("右", "Right")
            case .displaySinglePoint: ("（单点）", "(single point)")
            case .displayClosedLoop: ("（闭环）", " (closed loop)")
            case .displayNoStroke: ("（无笔画）", "(no stroke)")
            case .displayUnnamed: ("（未命名）", "(unnamed)")
            case .displayGeneralTarget: ("全局", "General")
            case .displayScrollHorizontal: ("横向滚动", "horizontal scroll")
            case .displayScrollVertical: ("纵向滚动", "vertical scroll")
            case .displayUnknownStepFormat: ("未知步骤（%@）", "unknown step (%@)")
            case .displayMouseLeft: ("鼠标左键", "left mouse button")
            case .displayMouseRight: ("鼠标右键", "right mouse button")
            case .displayMouseCenter: ("鼠标中键", "middle mouse button")
            case .displayMouseSide1: ("鼠标侧键 1", "mouse button 4")
            case .displayMouseSide2: ("鼠标侧键 2", "mouse button 5")
            case .displayScrollUpFormat: ("滚动%@", "scroll %@")
            case .displayScrollDownFormat: ("滚动%@", "scroll %@")
            case .displayScrollLeftFormat: ("滚动%@", "scroll %@")
            case .displayScrollRightFormat: ("滚动%@", "scroll %@")
            case .displayEmptyKeySequence: ("按键序列（空）", "key sequence (empty)")
            case .displayWebSearch: ("Web 搜索", "Web Search")
            case .displayWebSearchHostFormat: ("Web 搜索（%@）", "Web Search (%@)")
            case .displayShellScript: ("Shell 脚本", "Shell script")
            case .displayShellScriptFormat: ("Shell: %@", "Shell: %@")
            case .displaySystemFunctionKeyFormat: ("系统功能键 %d", "system function key %d")
            case .displayUnsupportedCommandFormat: ("不支持的命令 %@", "unsupported command %@")
            case .edgeTop: ("屏幕上边缘", "top edge")
            case .edgeBottom: ("屏幕下边缘", "bottom edge")
            case .edgeLeft: ("屏幕左边缘", "left edge")
            case .edgeRight: ("屏幕右边缘", "right edge")
            case .edgeTopLeft: ("屏幕左上角", "top-left corner")
            case .edgeTopRight: ("屏幕右上角", "top-right corner")
            case .edgeBottomLeft: ("屏幕左下角", "bottom-left corner")
            case .edgeBottomRight: ("屏幕右下角", "bottom-right corner")
            case .edgeUnknownFormat: ("未知边角(%d)", "unknown edge (%d)")
            case .systemFunctionBrightnessDown: ("降低亮度", "Brightness Down")
            case .systemFunctionBrightnessUp: ("增加亮度", "Brightness Up")
            case .systemFunctionPreviousTrack: ("上一曲", "Previous Track")
            case .systemFunctionPlayPause: ("播放/暂停", "Play/Pause")
            case .systemFunctionNextTrack: ("下一曲", "Next Track")
            case .systemFunctionMute: ("静音", "Mute")
            case .systemFunctionVolumeDown: ("降低音量", "Volume Down")
            case .systemFunctionVolumeUp: ("增加音量", "Volume Up")
            case .targetModeFocused:
                ("活动的应用程序和窗口", "The active application and window")
            case .targetModeUnderCursor:
                ("鼠标指针下方的应用程序和窗口", "The application and window under the pointer")
            }
        }
    }
}
