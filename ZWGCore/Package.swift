// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZWGCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZWGCore", targets: ["ZWGCore"])
    ],
    targets: [
        .target(
            name: "ZWGCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ZWGCoreTests",
            dependencies: ["ZWGCore"],
            // The reference configuration the compatibility tests run against. Committed on
            // purpose: reading the live installation made the suite machine-dependent (see
            // Tests/ZWGCoreTests/Fixtures/README.md).
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
