// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StuffTools",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "stuff", targets: ["StuffTool"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            exact: "1.8.2",
        ),
        .package(
            url: "https://github.com/swiftlang/swift-subprocess",
            exact: "1.0.0",
        ),
    ],
    targets: [
        .target(
            name: "StuffToolCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            path: "Sources/StuffToolCore",
        ),
        .executableTarget(
            name: "StuffTool",
            dependencies: [
                "StuffToolCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/StuffTool",
        ),
        .testTarget(
            name: "StuffToolCoreTests",
            dependencies: ["StuffTool", "StuffToolCore"],
            path: "SwiftTests/StuffToolCoreTests",
            resources: [.copy("Fixtures")],
        ),
    ],
)
