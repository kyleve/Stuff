// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TestImpact",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "test-impact-index", targets: ["TestImpactIndex"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", exact: "603.0.2"),
        .package(
            url: "https://github.com/swiftlang/indexstore-db",
            revision: "441ead7772cc391e2a0cc8318292bc4aaa8c3a6d",
        ),
    ],
    targets: [
        .executableTarget(
            name: "TestImpactIndex",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "IndexStoreDB", package: "indexstore-db"),
            ],
            path: "Sources",
        ),
        .testTarget(name: "TestImpactIndexTests", dependencies: ["TestImpactIndex"], path: "Tests"),
    ],
)
