import Foundation
import Testing

@testable import ZWGCore

@Suite("辅助功能授权：区分「还没给」与「更新弄丢了」")
struct AccessibilityGrantAssessmentTests {
    @Test("已授权时不看历史")
    func grantedIgnoresHistory() {
        #expect(AccessibilityGrantAssessment.assess(
            isTrusted: true,
            hasEverRunGranted: false
        ) == .granted)
        #expect(AccessibilityGrantAssessment.assess(
            isTrusted: true,
            hasEverRunGranted: true
        ) == .granted)
    }

    @Test("从来没授权过：这是首次运行路径")
    func neverGranted() {
        #expect(AccessibilityGrantAssessment.assess(
            isTrusted: false,
            hasEverRunGranted: false
        ) == .notGrantedYet)
    }

    @Test("以前授权过、现在没了：更新把授权弄丢了")
    func lostAfterUpdate() {
        // 未签名的构建里这是每次更新都会发生的事，也是「App 在跑但画手势没反应」的主因。
        #expect(AccessibilityGrantAssessment.assess(
            isTrusted: false,
            hasEverRunGranted: true
        ) == .lostAfterUpdate)
    }
}

@Suite("授权历史标记：只留一个布尔，且不碰用户配置")
struct PermissionHistoryTests {
    /// 每次用一个独立的 suite，互不干扰，也不写进真实用户偏好。
    private func makeSuite() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "zwg-permission-history-\(UUID().uuidString)"))
    }

    @Test("初始为「从未跑过」，记录一次后变 true，重复记录幂等")
    func recordsTheFirstGrant() throws {
        let history = PermissionHistory(defaults: try makeSuite())
        #expect(history.hasEverRunGranted == false)

        history.recordGranted()
        #expect(history.hasEverRunGranted == true)

        history.recordGranted()
        #expect(history.hasEverRunGranted == true)
    }

    @Test("标记跟着传入的 UserDefaults 走，两个 suite 互不影响")
    func suitesAreIsolated() throws {
        let granted = try makeSuite()
        let fresh = try makeSuite()

        PermissionHistory(defaults: granted).recordGranted()

        #expect(PermissionHistory(defaults: granted).hasEverRunGranted)
        #expect(PermissionHistory(defaults: fresh).hasEverRunGranted == false)
    }

    @Test("标记能被重新读出来 —— 它必须在重新启动应用之后仍然有效")
    func survivesANewInstance() throws {
        let suite = try makeSuite()
        PermissionHistory(defaults: suite).recordGranted()
        // 新的实例、同一个 suite，模拟下次启动。
        #expect(PermissionHistory(defaults: suite).hasEverRunGranted)
    }
}
