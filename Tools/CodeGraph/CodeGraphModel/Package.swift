// swift-tools-version: 6.2
import PackageDescription

/// Dependency-free model package shared by the code-graph-extract CLI and the
/// Catalyst viewer. Keeping it free of heavy/platform-specific dependencies
/// (e.g. indexstore-db) lets the iOS/Mac Catalyst viewer consume it cleanly.
let package = Package(
    name: "CodeGraphModel",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "CodeGraphModel", targets: ["CodeGraphModel"]),
    ],
    targets: [
        .target(
            name: "CodeGraphModel",
            resources: [
                .process("Resources"),
            ],
        ),
        .testTarget(
            name: "CodeGraphModelTests",
            dependencies: [
                "CodeGraphModel",
            ],
        ),
    ],
)
