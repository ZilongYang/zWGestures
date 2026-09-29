import CoreGraphics
import Testing

@testable import ZWGCore

@Suite("事件拦截器的事件掩码：绝不碰键盘")
struct EventTapMaskTests {
    @Test("指针与滚轮事件都必须在掩码里")
    func capturesPointerAndScroll() {
        let required: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved,
            .scrollWheel,
        ]
        for type in required {
            #expect(EventTapMask.contains(type), "\(type.rawValue) 应当在掩码里")
        }
    }

    @Test("键盘类型绝不在掩码里 —— 这是 2026-09-29 整机输入冻结的根因")
    func neverCapturesTheKeyboard() {
        for type in EventTapMask.forbiddenKeyboardTypes {
            #expect(!EventTapMask.contains(type), "\(type.rawValue) 绝不能被 tap 捕获")
        }
    }

    @Test("掩码的位数与列出的类型数一致：没有重复，也没有多余的位")
    func hasNoStrayBits() {
        #expect(EventTapMask.mask.nonzeroBitCount == EventTapMask.types.count)
    }

    @Test("系统伪事件不在掩码里（tap 不能主动申请它们）")
    func excludesSystemPseudoEvents() {
        #expect(!EventTapMask.contains(.tapDisabledByTimeout))
        #expect(!EventTapMask.contains(.tapDisabledByUserInput))
    }
}
