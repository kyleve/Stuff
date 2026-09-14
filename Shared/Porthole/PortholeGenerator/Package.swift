// swift-tools-version: 6.2
import PackageDescription

/// Host-only validation avoids planning the repository's iOS binary dependencies.
let package = Package(
    name: "PortholeGeneratorHost",
    platforms: [.macOS(.v15)],
    dependencies: [.package(
        url: "https://github.com/swiftlang/swift-syntax.git",
        exact: "603.0.2",
    )],
    targets: [
        .executableTarget(name: "PortholeGenerator", dependencies: [
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
        ], path: "Sources"),
        .testTarget(
            name: "PortholeGeneratorTests",
            dependencies: ["PortholeGenerator"],
            path: "Tests",
        ),
    ],
)
