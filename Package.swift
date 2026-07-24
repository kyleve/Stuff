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
        .library(name: "LifecycleKit", targets: ["LifecycleKit"]),
        .library(name: "JournalKit", targets: ["JournalKit"]),
        .library(name: "PeriscopeCore", targets: ["PeriscopeCore"]),
        .library(name: "PeriscopeUI", targets: ["PeriscopeUI"]),
        .library(name: "PeriscopeTools", targets: ["PeriscopeTools"]),
        .library(name: "SwiftDataInspector", targets: ["SwiftDataInspector"]),
        .library(name: "TestHostSupport", targets: ["TestHostSupport"]),
        .library(name: "RegionKit", targets: ["RegionKit"]),
        .library(name: "WhereCore", targets: ["WhereCore"]),
        .library(name: "WhereUI", targets: ["WhereUI"]),
        .library(name: "WhereIntents", targets: ["WhereIntents"]),
        .library(name: "BroadwayCore", targets: ["BroadwayCore"]),
        .library(name: "BroadwayUI", targets: ["BroadwayUI"]),
        .library(name: "PortholeCore", targets: ["PortholeCore"]),
        .library(name: "PortholeKit", targets: ["PortholeKit"]),
        .library(name: "PortholeKitUI", targets: ["PortholeKitUI"]),
        .library(name: "PortholeClientKit", targets: ["PortholeClientKit"]),
        .library(name: "PortholeMCP", targets: ["PortholeMCP"]),
        .library(name: "PortholeCLICore", targets: ["PortholeCLICore"]),
        .library(name: "PortholeLifecycle", targets: ["PortholeLifecycle"]),
        .library(name: "PortholeSwiftData", targets: ["PortholeSwiftData"]),
        .library(name: "PortholePeriscope", targets: ["PortholePeriscope"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        // Pinned to a main revision rather than 0.9.0: that release's
        // NetworkTransport has a Swift 6 strict-concurrency error under the
        // current toolchain, fixed on main (a `MainFlag` reference replaced a
        // captured `var`). Move to the next tagged release that includes it.
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk",
            revision: "a0ae212ebf6eab5f754c3129608bc5557637e605",
        ),
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
            name: "SwiftDataInspector",
            path: "Shared/SwiftDataInspector/Sources",
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
            name: "WhereCore",
            dependencies: [
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
                .target(name: "LifecycleKit"),
                .target(name: "PeriscopeCore"),
                .target(name: "PeriscopeTools"),
                .target(name: "PeriscopeUI"),
                .target(name: "RegionKit"),
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
        .target(
            name: "PortholeCore",
            path: "Shared/Porthole/PortholeCore/Sources",
        ),
        .target(
            name: "PortholeKit",
            dependencies: [
                .target(name: "PortholeCore"),
            ],
            path: "Shared/Porthole/PortholeKit/Sources",
        ),
        .target(
            name: "PortholeKitUI",
            dependencies: [
                .target(name: "PortholeKit"),
                .target(name: "BroadwayCore"),
                .target(name: "BroadwayUI"),
            ],
            path: "Shared/Porthole/PortholeKitUI/Sources",
        ),
        .target(
            name: "PortholeClientKit",
            dependencies: [
                .target(name: "PortholeCore"),
            ],
            path: "Shared/Porthole/PortholeClientKit/Sources",
        ),
        .target(
            name: "PortholeMCP",
            dependencies: [
                .target(name: "PortholeClientKit"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Shared/Porthole/PortholeMCP/Sources",
        ),
        .target(
            name: "PortholeCLICore",
            dependencies: [
                .target(name: "PortholeClientKit"),
                .target(name: "PortholeMCP"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Shared/Porthole/PortholeCLICore/Sources",
        ),
        .target(
            name: "PortholeLifecycle",
            dependencies: [
                .target(name: "PortholeKit"),
                .target(name: "LifecycleKit"),
            ],
            path: "Shared/Porthole/PortholeLifecycle/Sources",
        ),
        .target(
            name: "PortholeSwiftData",
            dependencies: [
                .target(name: "PortholeKit"),
                .target(name: "SwiftDataInspector"),
            ],
            path: "Shared/Porthole/PortholeSwiftData/Sources",
        ),
        .target(
            name: "PortholePeriscope",
            dependencies: [
                .target(name: "PortholeKit"),
                .target(name: "PeriscopeCore"),
            ],
            path: "Shared/Porthole/PortholePeriscope/Sources",
        ),
    ],
)
