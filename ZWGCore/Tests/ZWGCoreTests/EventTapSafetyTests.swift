import AppKit
import Testing

@testable import ZWGCore

@Suite("事件拦截器自保：超时到上限就放弃，而不是无限重新启用")
struct EventTapHealthPolicyTests {
    @Test("窗口内累积到超过上限才放弃")
    func givesUpOnlyAfterTooManyTimeouts() {
        var policy = EventTapHealthPolicy(maxTimeouts: 3, window: 60)

        #expect(policy.recordTimeout(at: 0) == false)
        #expect(policy.recordTimeout(at: 1) == false)
        #expect(policy.recordTimeout(at: 2) == false)
        // 第 4 次越过阈值：继续重新启用就是把系统拖回一个跟不上的 tap
        #expect(policy.recordTimeout(at: 3) == true)
        #expect(policy.recentTimeoutCount == 4)
    }

    @Test("窗口外的旧超时会被清掉，偶发超时不会累积成放弃")
    func oldTimeoutsFallOutOfTheWindow() {
        var policy = EventTapHealthPolicy(maxTimeouts: 3, window: 60)

        // 每 100 秒才超时一次：来多少次都不该停掉引擎
        for index in 0..<10 {
            #expect(policy.recordTimeout(at: Double(index) * 100) == false)
        }
        #expect(policy.recentTimeoutCount == 1)
    }

    @Test("2026-09-29 那次整机冻结的节奏会被拦下")
    func catchesTheRealIncident() {
        // 实测会话：22:56:12 起，超时以 15/4/17/17 秒的间隔出现。
        // 旧实现在 10 分钟里重新启用了 42 次；新规则在 36 秒处就该放弃。
        var policy = EventTapHealthPolicy()
        let offsets: [TimeInterval] = [0, 15, 19, 36, 53]
        let verdicts = offsets.map { policy.recordTimeout(at: $0) }

        #expect(verdicts.contains(true))
        #expect(verdicts.firstIndex(of: true) == 3)
    }

    @Test("reset 之后重新计数（用户手动重新启用）")
    func resetClearsTheWindow() {
        var policy = EventTapHealthPolicy(maxTimeouts: 3, window: 60)
        for index in 0..<4 {
            _ = policy.recordTimeout(at: Double(index))
        }
        policy.reset()
        #expect(policy.recentTimeoutCount == 0)
        #expect(policy.recordTimeout(at: 100) == false)
    }

    @Test("失败原因是给用户看的中文文案，且带次数")
    func failureReasonIsUserFacing() {
        let reason = EventTapHealthPolicy.failureReason(count: 4)
        #expect(reason.contains("4"))
        #expect(reason.contains("停用"))
    }

    /// 2026-10-06：用户报「画手势时偶尔有一丁点迟滞」。冻结修复把 **两种** 系统停用都塞进
    /// 了 0.5 秒退避，而旧逻辑是立刻重新启用。只有 `tapDisabledByTimeout` 才是「回调慢」的证据；
    /// `tapDisabledByUserInput` 与回调速度无关，让它等半秒等于白白丢掉半秒的手势输入。
    @Test("用户输入导致的停用立刻恢复，只有超时才退避")
    func userInputDisableIsReEnabledImmediately() {
        var policy = EventTapHealthPolicy()

        #expect(policy.action(for: .userInput, at: 0) == .reEnableNow)
        // 连来多次也一样：它不是超时，不该累积、更不该放弃。
        #expect(policy.action(for: .userInput, at: 1) == .reEnableNow)
        #expect(policy.action(for: .userInput, at: 2) == .reEnableNow)
        #expect(policy.action(for: .userInput, at: 3) == .reEnableNow)
        #expect(policy.recentTimeoutCount == 0, "用户输入的停用不该计入超时预算")

        #expect(policy.action(for: .timeout, at: 10) == .reEnableAfterBackoff(0.5))
        #expect(policy.action(for: .timeout, at: 11) == .reEnableAfterBackoff(0.5))
        #expect(policy.action(for: .timeout, at: 12) == .reEnableAfterBackoff(0.5))
        #expect(policy.action(for: .timeout, at: 13) == .giveUp(timeoutCount: 4))
    }
}

@Suite("急停快捷键：只认 ⌃⌥⌘⎋")
struct PanicShortcutTests {
    private static let escape = PanicShortcut.escapeKeyCode
    /// `kVK_ANSI_A`
    private static let letterA: UInt16 = 0

    private static func flags(_ set: NSEvent.ModifierFlags) -> UInt { set.rawValue }

    @Test("⌃⌥⌘⎋ 命中")
    func matchesTheShortcut() {
        #expect(PanicShortcut.matches(
            keyCode: Self.escape,
            modifierFlags: Self.flags([.control, .option, .command])
        ))
    }

    @Test("少任何一个修饰键都不命中")
    func requiresEveryModifier() {
        #expect(!PanicShortcut.matches(
            keyCode: Self.escape,
            modifierFlags: Self.flags([.control, .option])
        ))
        #expect(!PanicShortcut.matches(
            keyCode: Self.escape,
            modifierFlags: Self.flags([.control, .command])
        ))
        #expect(!PanicShortcut.matches(
            keyCode: Self.escape,
            modifierFlags: Self.flags([.option, .command])
        ))
    }

    @Test("多一个 ⇧ 不命中 —— 不能和系统强退快捷键混掉")
    func extraShiftDoesNotMatch() {
        #expect(!PanicShortcut.matches(
            keyCode: Self.escape,
            modifierFlags: Self.flags([.control, .option, .command, .shift])
        ))
    }

    @Test("光秃秃的 ⎋ 与别的键都不命中")
    func ignoresPlainEscapeAndOtherKeys() {
        #expect(!PanicShortcut.matches(keyCode: Self.escape, modifierFlags: 0))
        #expect(!PanicShortcut.matches(
            keyCode: Self.letterA,
            modifierFlags: Self.flags([.control, .option, .command])
        ))
    }

    @Test("caps lock / fn / 小键盘等设备标志位不影响判定")
    func ignoresUnrelatedDeviceFlags() {
        let noisy: NSEvent.ModifierFlags = [
            .control, .option, .command, .function, .numericPad, .capsLock,
        ]
        #expect(PanicShortcut.matches(
            keyCode: Self.escape,
            modifierFlags: Self.flags(noisy)
        ))
    }
}
