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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
