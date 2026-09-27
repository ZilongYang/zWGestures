import Testing

@testable import ZWGCore

@Test("应用以原生 arm64 运行，不依赖 Rosetta")
func runsNativeOnAppleSilicon() {
    #if arch(arm64)
    #expect(BuildInfo.isAppleSiliconNative)
    #expect(BuildInfo.isTranslated == false)
    #else
    Issue.record("测试宿主不是 arm64：\(BuildInfo.architecture)")
    #endif
}
