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
        let pair = key.pair
        return lock.withLock { current == .en ? pair.en : pair.zh }
    }

    /// 带参数的文案（占位符两语言必须一致，`L10nTests` 会检查）。
    public static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// 语言偏好设置项自身的名字。
    public enum Key: CaseIterable, Sendable {
        // MARK: 语言
        case languageSystem
        case languageSection
        case prefsLanguageHelp

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
