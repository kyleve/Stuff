// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stuff",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "StuffCore", targets: ["StuffCore"]),
        .library(name: "CreditKit", targets: ["CreditKit"]),
        .library(name: "LedgerCore", targets: ["LedgerCore"]),
        .library(name: "LifecycleKit", targets: ["LifecycleKit"]),
        .library(name: "LifecycleKitUI", targets: ["LifecycleKitUI"]),
        .library(name: "JournalKit", targets: ["JournalKit"]),
        .library(name: "KeychainKit", targets: ["KeychainKit"]),
        .library(name: "PeriscopeCore", targets: ["PeriscopeCore"]),
        .library(name: "PeriscopeUI", targets: ["PeriscopeUI"]),
        .library(name: "PeriscopeTools", targets: ["PeriscopeTools"]),
        .library(name: "Inspector", targets: ["Inspector"]),
        .library(name: "Flyover", targets: ["Flyover"]),
        .library(name: "SnapshotKit", targets: ["SnapshotKit"]),
        .library(name: "SnapshotKitTesting", targets: ["SnapshotKitTesting"]),
        .library(name: "TestHostSupport", targets: ["TestHostSupport"]),
        .library(name: "RegionKit", targets: ["RegionKit"]),
        .library(name: "WhereCrashReporting", targets: ["WhereCrashReporting"]),
        .library(name: "WhereCore", targets: ["WhereCore"]),
        .library(name: "WhereUI", targets: ["WhereUI"]),
        .library(name: "WhereIntents", targets: ["WhereIntents"]),
        .library(name: "BroadwayCore", targets: ["BroadwayCore"]),
        .library(name: "BroadwayUI", targets: ["BroadwayUI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/RoyalPineapple/BumperBowling.git",
            branch: "main",
        ),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(url: "https://github.com/bitdriftlabs/capture-ios.git", from: "0.23.11"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.25.0"),
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
            name: "CreditKit",
            path: "Shared/CreditKit/Sources",
        ),
        .target(
            name: "LedgerCore",
            dependencies: [
                .target(name: "KeychainKit"),
                .target(name: "PeriscopeCore"),
            ],
            path: "Ledger/LedgerCore/Sources",
        ),
        .target(
            name: "LifecycleKit",
            path: "Shared/LifecycleKit/Sources",
        ),
        .target(
            name: "LifecycleKitUI",
            dependencies: [
                .target(name: "LifecycleKit"),
            ],
            path: "Shared/LifecycleKitUI/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "JournalKit",
            path: "Shared/JournalKit/Sources",
        ),
        .target(
            name: "KeychainKit",
            path: "Shared/KeychainKit/Sources",
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
                .target(name: "BroadwayCore"),
                .target(name: "BroadwayUI"),
            ],
            path: "Shared/Periscope/PeriscopeTools/Sources",
        ),
        .target(
            name: "Inspector",
            path: "Shared/Inspector/Sources",
        ),
        .target(
            name: "Flyover",
            dependencies: [
                .target(name: "BroadwayCore"),
                .target(name: "BroadwayUI"),
                .target(name: "SnapshotKit"),
            ],
            path: "Shared/Flyover/Sources",
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
                // Keep the focused Core + SwiftUI renderer products: the
                // umbrella additionally pulls in AccessibilitySnapshot's own
                // SnapshotTesting integration, widening every consuming test
                // bundle's statically embedded closure for no benefit.
                .product(name: "AccessibilitySnapshotCore", package: "AccessibilitySnapshot"),
                .product(name: "AccessibilitySnapshotPreviews", package: "AccessibilitySnapshot"),
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
                .target(name: "PeriscopeCore"),
            ],
            path: "Where/RegionKit/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "WhereCrashReporting",
            dependencies: [
                .product(name: "Capture", package: "capture-ios"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: "Where/WhereCrashReporting/Sources",
        ),
        .target(
            name: "WhereCore",
            dependencies: [
                .target(name: "CreditKit"),
                .target(name: "JournalKit"),
                .target(name: "KeychainKit"),
                .target(name: "PeriscopeCore"),
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
                .target(name: "CreditKit"),
                .target(name: "Flyover"),
                .target(name: "LifecycleKit"),
                .target(name: "LifecycleKitUI"),
                .target(name: "PeriscopeCore"),
                .target(name: "PeriscopeTools"),
                .target(name: "PeriscopeUI"),
                .target(name: "RegionKit"),
                .target(name: "SnapshotKit"),
                .target(name: "Inspector"),
            ],
            path: "Where/WhereUI/Sources",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "WhereIntents",
            dependencies: [
                .target(name: "PeriscopeCore"),
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
