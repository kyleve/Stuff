// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeGraph",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
    ],
    products: [
        .library(name: "CodeGraphModel", targets: ["CodeGraphModel"]),
        .executable(name: "code-graph-extract", targets: ["code-graph-extract"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/indexstore-db.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CodeGraphModel",
            resources: [
                .process("Resources"),
            ],
        ),
        .executableTarget(
            name: "code-graph-extract",
            dependencies: [
                "CodeGraphModel",
                .product(name: "IndexStoreDB", package: "indexstore-db"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
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
