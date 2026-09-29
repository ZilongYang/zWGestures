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

    /// `zWGestures/Resources/Defaults`, or `nil` when it has not been generated yet.
    static var appDefaults: URL? {
        let directory = root.appendingPathComponent("zWGestures/Resources/Defaults", isDirectory: true)
        let gestures = directory.appendingPathComponent("gestures.json")
        return FileManager.default.fileExists(atPath: gestures.path) ? directory : nil
    }

    /// The committed reference configuration (`ZWGCoreTests/Fixtures/...`), copied into the test
    /// bundle by `Package.swift`. Kept here so the two path helpers sit together.
    static var fixturesRoot: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures", isDirectory: true)
    }
}
