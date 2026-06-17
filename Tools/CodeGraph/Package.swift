// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeGraph",
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
