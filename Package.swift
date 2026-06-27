// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stuff",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "StuffCore", targets: ["StuffCore"]),
        .library(name: "LocalizationKit", targets: ["LocalizationKit"]),
        .library(name: "LifecycleKit", targets: ["LifecycleKit"]),
        .library(name: "LogKit", targets: ["LogKit"]),
        .library(name: "LogViewerUI", targets: ["LogViewerUI"]),
        .library(name: "SwiftDataInspector", targets: ["SwiftDataInspector"]),
        .library(name: "WhereCore", targets: ["WhereCore"]),
        .library(name: "WhereUI", targets: ["WhereUI"]),
        .library(name: "WhereTesting", targets: ["WhereTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
    ],
    targets: [
        .target(
            name: "StuffCore",
            path: "Shared/StuffCore/Sources",
        ),
        .target(
            name: "LocalizationKit",
            path: "Shared/LocalizationKit/Sources",
        ),
        .target(
            name: "LifecycleKit",
            path: "Shared/LifecycleKit/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "LogKit",
            path: "Shared/LogKit/Sources",
        ),
        .target(
            name: "LogViewerUI",
            dependencies: [
                .target(name: "LogKit"),
            ],
            path: "Shared/LogViewerUI/Sources",
        ),
        .target(
            name: "SwiftDataInspector",
            path: "Shared/SwiftDataInspector/Sources",
        ),
        .target(
            name: "WhereCore",
            dependencies: [
                .target(name: "LogKit"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Where/WhereCore/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "WhereUI",
            dependencies: [
                .target(name: "StuffCore"),
                .target(name: "WhereCore"),
                .target(name: "LifecycleKit"),
                .target(name: "LogKit"),
                .target(name: "LogViewerUI"),
                .target(name: "SwiftDataInspector"),
            ],
            path: "Where/WhereUI/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "WhereTesting",
            dependencies: [
                .target(name: "WhereCore"),
            ],
            path: "Where/WhereTesting/Sources",
        ),
    ],
)
