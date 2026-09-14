// swift-tools-version: 6.2
import Foundation
import PackageDescription

/// Share the existing icon catalog without making unrelated Where files target inputs.
/// Kept paths include whole source/resource directories; only their ancestors are enumerated.
func excludingSiblings(of keptPaths: [String], under targetPath: String) throws -> [String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent(targetPath)
    func excludedChildren(at relativePath: String) throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: root.appendingPathComponent(relativePath).path)
            .sorted().flatMap { child -> [String] in
                let path = relativePath.isEmpty ? child : relativePath + "/" + child
                if keptPaths.contains(path) { return [] }
                if keptPaths.contains(where: { $0.hasPrefix(path + "/") }) {
                    return try excludedChildren(at: path)
                }
                return [path]
            }
    }
    return try excludedChildren(at: "")
}

let package = try Package(
    name: "Stuff",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .executable(name: "porthole", targets: ["PortholeCLI"]),
        .library(name: "PortholeUI", targets: ["PortholeUI"]),
        .library(name: "PortholeAgent", targets: ["PortholeAgent"]),
        .library(name: "PortholeRemote", targets: ["PortholeRemote"]),
        .library(name: "PortholeGitHub", targets: ["PortholeGitHub"]),
        .library(name: "PortholeJavaScript", targets: ["PortholeJavaScript"]),
        .library(name: "PortholeCore", targets: ["PortholeCore"]),
        .library(name: "PortholeRuntime", targets: ["PortholeRuntime"]),
        .library(name: "CreditKit", targets: ["CreditKit"]),
        .library(name: "LedgerCore", targets: ["LedgerCore"]),
        .library(name: "LifecycleKit", targets: ["LifecycleKit"]),
        .library(name: "LifecycleKitUI", targets: ["LifecycleKitUI"]),
        .library(name: "JournalKit", targets: ["JournalKit"]),
        .library(name: "PeriscopeCore", targets: ["PeriscopeCore"]),
        .library(name: "PeriscopeUI", targets: ["PeriscopeUI"]),
        .library(name: "PeriscopeTools", targets: ["PeriscopeTools"]),
        .library(name: "Inspector", targets: ["Inspector"]),
        .library(name: "Flyover", targets: ["Flyover"]),
        .library(name: "SnapshotKit", targets: ["SnapshotKit"]),
        .library(name: "SnapshotKitTesting", targets: ["SnapshotKitTesting"]),
        .library(name: "TestHostSupport", targets: ["TestHostSupport"]),
        .library(name: "RegionKit", targets: ["RegionKit"]),
        // Keep the host and extension dependency closure in one shared image.
        .library(
            name: "WhereApplicationSupport",
            type: .dynamic,
            targets: ["WhereUI", "WhereIntents", "WhereCrashReporting"],
        ),
        .library(name: "WhereCrashReporting", targets: ["WhereCrashReporting"]),
        .library(name: "WhereCore", targets: ["WhereCore"]),
        .library(name: "WhereAssets", targets: ["WhereAssets"]),
        .library(name: "WhereUI", targets: ["WhereUI"]),
        .library(name: "WhereIntents", targets: ["WhereIntents"]),
        .library(name: "BroadwayCore", targets: ["BroadwayCore"]),
        .library(name: "BroadwayUI", targets: ["BroadwayUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/zaidmukaddam/swift-ai-sdk.git", exact: "0.3.0"),
        .package(path: "Shared/Porthole/PortholeCertificates"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
        .package(
            url: "https://github.com/RoyalPineapple/BumperBowling.git",
            branch: "main",
        ),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(url: "https://github.com/bitdriftlabs/capture-ios.git", from: "0.23.11"),
        // Snapshot-testing engine + accessibility parser. Consumed only by the
        // test-only `SnapshotKitTesting` target (never a shipping app). See
        // Shared/SnapshotKitTesting.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
        .package(url: "https://github.com/cashapp/AccessibilitySnapshot", from: "0.12.0"),
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "PortholeCLI",
            dependencies: [
                .target(name: "PortholeCore"),
                .target(name: "PortholeRemote"),
            ],
            path: "Shared/Porthole/PortholeCLI/Sources",
        ),
        .target(
            name: "PortholeUI",
            dependencies: [
                .target(name: "PortholeRuntime"),
                .target(name: "PortholeJavaScript"),
                .target(name: "PortholeAgent"),
                .target(name: "PortholeGitHub"),
                .target(name: "PortholeRemote"),
                .target(name: "BroadwayCore", condition: .when(platforms: [.iOS, .macCatalyst])),
                .target(
                    name: "BroadwayUI",
                    condition: .when(platforms: [.iOS, .macCatalyst]),
                ),
                .target(name: "SnapshotKit", condition: .when(platforms: [.iOS, .macCatalyst])),
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
            ],
            path: "Shared/Porthole/PortholeUI/Sources",
        ),
        .target(
            name: "PortholeAgent",
            dependencies: [
                .target(name: "PortholeCore"),
                .product(name: "AI", package: "swift-ai-sdk"),
            ],
            path: "Shared/Porthole/PortholeAgent/Sources",
        ),
        .target(
            name: "PortholeRemote",
            dependencies: [
                .target(name: "PortholeCore"),
                .product(name: "PortholeCertificates", package: "PortholeCertificates"),
            ],
            path: "Shared/Porthole/PortholeRemote/Sources",
        ),
        .target(
            name: "PortholeGitHub",
            path: "Shared/Porthole/PortholeGitHub/Sources",
        ),
        .target(
            name: "CQuickJS",
            path: "Shared/Porthole/CQuickJS/Sources",
            publicHeadersPath: "include",
            cSettings: [.define("QUICKJS_NG_BUILD"), .define("_GNU_SOURCE")],
        ),
        .target(
            name: "PortholeJavaScript",
            dependencies: [.target(name: "CQuickJS"), .target(name: "PortholeCore")],
            path: "Shared/Porthole/PortholeJavaScript/Sources",
        ),
        .executableTarget(
            name: "PortholeGenerator",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            path: "Shared/Porthole/PortholeGenerator/Sources",
        ),
        .plugin(
            name: "PortholeBuildPlugin",
            capability: .buildTool(),
            dependencies: [.target(name: "PortholeGenerator")],
            path: "Shared/Porthole/PortholeBuildPlugin",
        ),
        .target(
            name: "PortholeCore",
            path: "Shared/Porthole/PortholeCore/Sources",
        ),
        .target(
            name: "PortholeRuntime",
            dependencies: [.target(name: "PortholeCore")],
            path: "Shared/Porthole/PortholeRuntime/Sources",
        ),
        .target(
            name: "CreditKit",
            path: "Shared/CreditKit/Sources",
        ),
        .target(
            name: "LedgerCore",
            dependencies: [
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
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
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
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
            ],
            path: "Shared/Periscope/PeriscopeTools/Sources",
        ),
        .target(
            name: "Inspector",
            dependencies: [
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
            ],
            path: "Shared/Inspector/Sources",
        ),
        .target(
            name: "Flyover",
            dependencies: [
                .target(name: "BroadwayCore"),
                .target(name: "BroadwayUI"),
                .target(name: "SnapshotKit"),
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
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
            ],
            path: "Where/WhereCrashReporting/Sources",
        ),
        .target(
            name: "WhereCore",
            dependencies: [
                .target(name: "CreditKit"),
                .target(name: "JournalKit"),
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
            name: "WhereAssets",
            path: "Where",
            exclude: excludingSiblings(of: [
                "WhereAssets/Sources",
                "WhereUI/Sources/Resources/AppIconPreviews.xcassets",
            ], under: "Where"),
            sources: ["WhereAssets/Sources"],
            resources: [.process("WhereUI/Sources/Resources/AppIconPreviews.xcassets")],
        ),
        .target(
            name: "WhereUI",
            dependencies: [
                .target(name: "PortholeUI"),
                .target(name: "WhereCore"),
                .target(name: "WhereAssets"),
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
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
            ],
            path: "Where/WhereUI/Sources",
            exclude: ["Resources/AppIconPreviews.xcassets"],
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

// Opt-in belongs to this adopting package. The reusable runtime has no unsafe
// flags. The normal-source CI pass compiles the same source and SDK without
// private binding bodies or disabled access control.
let originalSourceCheck = ProcessInfo.processInfo.environment["PORTHOLE_ORIGINAL_SOURCE_CHECK"] == "1"
var portholeModules: Set<String> = []
@MainActor
func includePortholeModule(_ name: String) {
    guard !name.hasPrefix("Porthole"), !name.hasPrefix("CQuickJS"),
          let target = package.targets.first(where: { $0.name == name }),
          portholeModules.insert(name).inserted else { return }
    for dependency in target.dependencies {
        switch dependency {
            case let .targetItem(name, _), let .byNameItem(name, _): includePortholeModule(name)
            case .productItem: break
            @unknown default: break
        }
    }
}

for root in ["WhereUI", "WhereIntents", "WhereCrashReporting"] {
    includePortholeModule(root)
}

for target in package.targets where portholeModules.contains(target.name) {
    target.dependencies.append(.target(name: "PortholeRuntime"))
    target.plugins = (target.plugins ?? []) + [.plugin(name: "PortholeBuildPlugin")]
    // Private imports preserve cross-file linkage without changing Xcode's compilation mode.
    target.swiftSettings = (target.swiftSettings ?? []) + (originalSourceCheck
        ? [.define("PORTHOLE_ORIGINAL_SOURCE_CHECK")]
        : [.unsafeFlags(["-Xfrontend", "-disable-access-control", "-enable-private-imports"])])
}
