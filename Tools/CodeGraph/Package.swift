// swift-tools-version: 6.2
import PackageDescription

/// The index-store extractor CLI. The shared graph schema lives in the
/// dependency-free CodeGraphModel package next door so the Catalyst viewer can
/// reuse it without pulling in indexstore-db (macOS-only).
let package = Package(
    name: "CodeGraph",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "code-graph-extract", targets: ["code-graph-extract"]),
    ],
    dependencies: [
        .package(path: "CodeGraphModel"),
        .package(url: "https://github.com/apple/indexstore-db.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "code-graph-extract",
            dependencies: [
                .product(name: "CodeGraphModel", package: "CodeGraphModel"),
                .product(name: "IndexStoreDB", package: "indexstore-db"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
    ],
)
