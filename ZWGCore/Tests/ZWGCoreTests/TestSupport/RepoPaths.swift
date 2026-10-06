import Foundation

/// Paths inside the repository itself, for tests that must read a committed file.
///
/// Resolved from this file's own location at compile time. Tests are not supposed to read the built
/// app bundle — `swift test` compiles ZWGCore on its own, with no bundle around it — but the
/// factory-default gesture pack only exists as an app resource. Testing the **exact artifact that
/// ships** is worth more than testing a second copy of it, so the same committed file is read here
/// through the source tree instead.
enum RepoPaths {
    /// The repository root.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestSupport/
            .deletingLastPathComponent()  // ZWGCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // ZWGCore/
            .deletingLastPathComponent()  // repository root
    }

    /// `zWGestures/Resources/Defaults`（两份语言包 + 译名表），尚未生成时为 `nil`。
    static var appDefaultsRoot: URL? {
        let directory = root.appendingPathComponent("zWGestures/Resources/Defaults", isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    /// 指定语言的默认手势包目录（`zh-Hans` / `en`）。
    static func appDefaults(_ language: String) -> URL? {
        guard let directory = appDefaultsRoot?.appendingPathComponent(language, isDirectory: true) else {
            return nil
        }
        let gestures = directory.appendingPathComponent("gestures.json")
        return FileManager.default.fileExists(atPath: gestures.path) ? directory : nil
    }

    /// 中文包（默认包）。
    static var appDefaults: URL? { appDefaults("zh-Hans") }

    /// 运行时译名表（英文 → 中文）。
    static var nameTranslations: URL? {
        let url = appDefaultsRoot?.appendingPathComponent("name-translations.json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The committed reference configuration (`ZWGCoreTests/Fixtures/...`), copied into the test
    /// bundle by `Package.swift`. Kept here so the two path helpers sit together.
    static var fixturesRoot: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures", isDirectory: true)
    }
}
