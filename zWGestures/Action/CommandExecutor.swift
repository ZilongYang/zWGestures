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
            WebSearchRunner.open(template: template, targetPID: context.targetPID)
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
    /// Everything that can be collected **without any cross-process call**.
    ///
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
            gestureStart: gestureStart,
            screenHeight: NSScreen.screens.first?.frame.height ?? 0
        )
    }

    /// How long a single Accessibility query may take before we give up on it.
    ///
    /// The system default is 6 seconds, and against an application that is not responding it can be
    /// far worse. `AXUIElementSetMessagingTimeout` is the only way to bound it.
    /// `nonisolated` so it can be a default argument of the nonisolated reader below.
    nonisolated static let windowTitleTimeout: Float = 0.25

    /// The focused window's title, read through the Accessibility API.
    ///
    /// Window titles are not available from `CGWindowListCopyWindowInfo` unless the process also
    /// holds Screen Recording permission, so the AX API is used instead.
    ///
    /// 🔴 **Never call this from the main actor.** It is a cross-process call: when the target
    /// application is busy or hung it blocks, and on 2026-10-06 a momentarily unresponsive browser
    /// held the main thread for **47 seconds** — every recognised gesture in that window silently
    /// failed to run and the app looked frozen until it crashed (docs/ROADMAP.md §22).
    ///
    /// It therefore runs on a background task with a short messaging timeout, and only for the
    /// commands that actually need it (`WGCommandPlan.needsTargetWindowTitle`).
    nonisolated static func windowTitle(
        for pid: Int32,
        timeout: Float = windowTitleTimeout
    ) async -> String? {
        await Task.detached(priority: .userInitiated) {
            readWindowTitle(pid: pid, timeout: timeout)
        }.value
    }

    /// The blocking half, on whatever thread the caller put it on.
    nonisolated private static func readWindowTitle(pid: Int32, timeout: Float) -> String? {
        let application = AXUIElementCreateApplication(pid)
        // Bound the wait *before* asking anything: the default is 6 s per message.
        AXUIElementSetMessagingTimeout(application, timeout)

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success, let window = windowValue else { return nil }
        let element = window as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)

        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success else { return nil }
        return titleValue as? String
    }
}
