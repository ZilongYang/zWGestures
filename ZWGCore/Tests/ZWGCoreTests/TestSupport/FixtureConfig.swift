import Foundation

/// The reference configuration the compatibility tests run against.
///
/// A copy of a real WGestures 2.3.3 configuration — the original's default gesture set plus the
/// author's own edits — lives in `Fixtures/legacy/2.3.3`. These tests used to read the live
/// installation under `~/Library/Application Support/com.yingdev.wgestures`, which made
/// `make test` depend on the machine: without a local WGestures install the tests were skipped
/// (so CI had no compatibility coverage at all), and one of them was not gated and simply failed.
///
/// `Bundle.module` resolves the copy SwiftPM puts in the test bundle, so the suite is
/// machine-independent. See `Fixtures/README.md` for provenance and for what to do when the
/// fixture changes.
enum FixtureConfig {
    /// `…/ZWGCore_ZWGCoreTests.bundle/Fixtures/legacy/2.3.3`
    static let directory: URL = {
        guard let root = Bundle.module.resourceURL else {
            fatalError("测试 bundle 没有 resourceURL —— SwiftPM 资源没打进来")
        }
        let url = root.appendingPathComponent("Fixtures/legacy/2.3.3", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("gestures.json").path) else {
            fatalError("""
                参考配置不在测试 bundle 里：\(url.path)
                检查 Package.swift 的 resources: [.copy("Fixtures")] 与
                Tests/ZWGCoreTests/Fixtures/legacy/2.3.3/。
                """)
        }
        return url
    }()
}
