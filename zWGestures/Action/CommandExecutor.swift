import AppKit
import CoreGraphics
import Foundation

/// Carries out the actions of a recognised gesture.
///
/// Runs on the main actor because activation and URL opening are AppKit operations, and only
/// ever gets there *after* the gesture has been recognised — the tap thread hands off and
/// returns immediately, so a slow command can never stall input handling.
@MainActor
final class CommandExecutor {
    /// Short description of the last executed command, for the debug HUD and the menu.
    private(set) var lastSummary: String?
    private(set) var executedCount = 0

    /// Delay between bringing a target application forward and sending its keys, so the
    /// keystrokes land in the app the user aimed at rather than the previous one.
    private let activationSettleDelay = Duration.milliseconds(50)

    func execute(plan: WGCommandPlan, intentName: String, context: WGActionContext) {
        guard plan.isExecutable else {
            let detail = plan.problems.isEmpty ? "没有可执行的动作" : plan.problems.joined(separator: "；")
            Log.action.error("手势「\(intentName, privacy: .public)」无法执行：\(detail, privacy: .public)")
            return
        }
        for problem in plan.problems {
            Log.action.warning("手势「\(intentName, privacy: .public)」：\(problem, privacy: .public)")
        }

        let run: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            for action in plan.actions {
                self.perform(action, context: context)
            }
            self.executedCount += 1
            self.lastSummary = "\(intentName)"
            Log.action.notice("""
                执行手势「\(intentName, privacy: .public)」：\
                \(plan.actions.count, privacy: .public) 个动作
                """)
        }

        if plan.activateTargetFirst, let application = targetApplication(for: context) {
            activate(application)
            Task { @MainActor in
                try? await Task.sleep(for: activationSettleDelay)
                run()
            }
        } else {
            run()
        }
    }

    // MARK: - Actions

    private func perform(_ action: WGPlannedAction, context: WGActionContext) {
        switch action {
        case .keyStroke(let modifiers, let flags, let keyCode):
            KeyEventPoster.postKeyStroke(modifiers: modifiers, flags: flags, keyCode: keyCode)

        case .modifierOnly(let flags):
            // A configuration that only holds modifiers has no key to press; releasing them is
            // the only sensible interpretation, which is what an empty press/release pair does.
            Log.action.warning("按键序列里有一步只包含修饰键（\(flags.rawValue, privacy: .public)），已跳过")

        case .systemFunction(let function):
            SystemFunctionPoster.post(function)

        case .runShellScript(let script):
            ShellScriptRunner.run(script: script, environment: context.environment())

        case .webSearch(let template):
            WebSearchRunner.open(template: template)
        }
    }

    // MARK: - Target application

    private func targetApplication(for context: WGActionContext) -> NSRunningApplication? {
        if let pid = context.targetPID, let application = NSRunningApplication(processIdentifier: pid) {
            return application
        }
        return NSWorkspace.shared.frontmostApplication
    }

    private func activate(_ application: NSRunningApplication) {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if !application.isActive {
            application.activate(from: .current, options: [])
        }
    }
}

/// Builds the action context for a gesture that has just been recognised.
@MainActor
enum ActionContextProvider {
    /// - Parameters:
    ///   - application: the application the gesture was aimed at, when it was resolved.
    ///   - windowID: window server id of the window under the gesture's start point.
    static func current(
        gestureStart: CGPoint,
        application: WGApplicationIdentity? = nil,
        windowID: Int? = nil
    ) -> WGActionContext {
        let resolved = application ?? NSWorkspace.shared.frontmostApplication.map {
            WGApplicationIdentity(
                pid: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier,
                executablePath: $0.executableURL?.path,
                localizedName: $0.localizedName
            )
        }

        return WGActionContext(
            targetPID: resolved?.pid,
            targetBundleIdentifier: resolved?.bundleIdentifier,
            targetExecutablePath: resolved?.executablePath,
            targetWindowID: windowID,
            targetAppName: resolved?.localizedName,
            targetWindowName: windowTitle(for: resolved?.pid),
            gestureStart: gestureStart,
            screenHeight: NSScreen.screens.first?.frame.height ?? 0
        )
    }

    /// The focused window's title, read through the Accessibility API.
    ///
    /// Window titles are not available from `CGWindowListCopyWindowInfo` unless the process also
    /// holds Screen Recording permission, so the AX API is used instead.
    private static func windowTitle(for pid: Int32?) -> String? {
        guard let pid else { return nil }
        let application = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success, let window = windowValue else { return nil }

        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success else { return nil }
        return titleValue as? String
    }
}
