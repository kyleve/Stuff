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
        .library(name: "LifecycleKit", targets: ["LifecycleKit"]),
        .library(name: "JournalKit", targets: ["JournalKit"]),
        .library(name: "LogKit", targets: ["LogKit"]),
        .library(name: "LogViewerUI", targets: ["LogViewerUI"]),
        .library(name: "PeriscopeCore", targets: ["PeriscopeCore"]),
        .library(name: "PeriscopeUI", targets: ["PeriscopeUI"]),
        .library(name: "PeriscopeTools", targets: ["PeriscopeTools"]),
        .library(name: "SwiftDataInspector", targets: ["SwiftDataInspector"]),
        .library(name: "SnapshotKit", targets: ["SnapshotKit"]),
        .library(name: "SnapshotKitTesting", targets: ["SnapshotKitTesting"]),
        .library(name: "TestHostSupport", targets: ["TestHostSupport"]),
        .library(name: "RegionKit", targets: ["RegionKit"]),
        .library(name: "WhereCore", targets: ["WhereCore"]),
        .library(name: "WhereUI", targets: ["WhereUI"]),
        .library(name: "WhereIntents", targets: ["WhereIntents"]),
        .library(name: "BroadwayCore", targets: ["BroadwayCore"]),
        .library(name: "BroadwayUI", targets: ["BroadwayUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        // Snapshot-testing engine + accessibility parser. Consumed only by the
        // test-only `SnapshotKitTesting` target (never a shipping app). See
        // Shared/SnapshotKitTesting.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
        .package(url: "https://github.com/cashapp/AccessibilitySnapshot", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "StuffCore",
            path: "Shared/StuffCore/Sources",
        ),
        .target(
            name: "LifecycleKit",
            path: "Shared/LifecycleKit/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "JournalKit",
            path: "Shared/JournalKit/Sources",
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
            name: "PeriscopeCore",
            dependencies: [
                .target(name: "JournalKit"),
            ],
            path: "Shared/Periscope/PeriscopeCore/Sources",
        ),
        .target(
            name: "PeriscopeUI",
            dependencies: [
                .target(name: "PeriscopeCore"),
            ],
            path: "Shared/Periscope/PeriscopeUI/Sources",
        ),
        .target(
            name: "PeriscopeTools",
            dependencies: [
                .target(name: "PeriscopeCore"),
                .target(name: "PeriscopeUI"),
            ],
            path: "Shared/Periscope/PeriscopeTools/Sources",
        ),
        .target(
            name: "SwiftDataInspector",
            path: "Shared/SwiftDataInspector/Sources",
        ),
        .target(
            name: "SnapshotKit",
            path: "Shared/SnapshotKit/Sources",
        ),
        .target(
            name: "SnapshotKitTesting",
            dependencies: [
                .target(name: "SnapshotKit"),
                .target(name: "TestHostSupport"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "AccessibilitySnapshot", package: "AccessibilitySnapshot"),
            ],
            path: "Shared/SnapshotKitTesting/Sources",
        ),
        .target(
            name: "TestHostSupport",
            path: "Shared/TestHostSupport/Sources",
        ),
        .target(
            name: "RegionKit",
            dependencies: [
                .target(name: "LogKit"),
            ],
            path: "Where/RegionKit/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "WhereCore",
            dependencies: [
                .target(name: "LogKit"),
                .target(name: "RegionKit"),
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
                .target(name: "WhereCore"),
                .target(name: "BroadwayCore"),
                .target(name: "BroadwayUI"),
                .target(name: "LifecycleKit"),
                .target(name: "LogKit"),
                .target(name: "LogViewerUI"),
                .target(name: "RegionKit"),
                .target(name: "SnapshotKit"),
                .target(name: "SwiftDataInspector"),
            ],
            path: "Where/WhereUI/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "WhereIntents",
            dependencies: [
                .target(name: "LogKit"),
                .target(name: "RegionKit"),
                .target(name: "WhereCore"),
                .target(name: "WhereUI"),
            ],
            path: "Where/WhereIntents/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "BroadwayCore",
            path: "Shared/Broadway/BroadwayCore/Sources",
        ),
        .target(
            name: "BroadwayUI",
            dependencies: [
                .target(name: "BroadwayCore"),
            ],
            path: "Shared/Broadway/BroadwayUI/Sources",
        ),
    ],
)
