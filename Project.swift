import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad]
let deployment: DeploymentTargets = .iOS("26.0")

/// Local Swift package (see root `Package.swift`) for the library products
/// (StuffCore, WhereCore, WhereUI, TestHostSupport, the Broadway modules, …).
private let stuffPackage = Package.local(path: .relativeToRoot("."))

/// Apple Developer Team used to code-sign when building to a device, read from
/// the `TUIST_DEVELOPMENT_TEAM` environment variable so each developer's team ID
/// stays out of the checked-in project. Set it in `.mise.local.toml` (gitignored)
/// and it's picked up automatically by `mise exec -- tuist generate` (i.e. `./ide`).
/// When unset — e.g. on CI or a fresh clone — no `DEVELOPMENT_TEAM` is written and
/// Xcode falls back to its defaults.
private let developmentTeam = Environment.developmentTeam.getString(default: "")

private let projectSettings: Settings? = developmentTeam.isEmpty
    ? nil
    : .settings(base: ["DEVELOPMENT_TEAM": .string(developmentTeam)])

/// App Group shared by the Where app, its widget extension, and its share
/// extension so every process sees the same on-disk SwiftData store (see
/// `SwiftDataStore.appGroupIdentifier`, which must match) and the widget
/// snapshot JSON.
let whereAppGroupEntitlements: Entitlements = .dictionary([
    "com.apple.security.application-groups": .array([.string("group.com.stuff.where")]),
])

func unitTests(
    name: String,
    bundleIdSuffix: String,
    productDependency: String,
    sources: ProjectDescription.SourceFilesList,
    extraPackageProducts: [String] = [],
) -> Target {
    var dependencies: [TargetDependency] = [
        .package(product: productDependency),
        .package(product: "TestHostSupport"),
        .target(name: "StuffTestHost"),
    ]
    for product in extraPackageProducts {
        dependencies.append(.package(product: product))
    }
    return .target(
        name: name,
        destinations: destinations,
        product: .unitTests,
        bundleId: "com.stuff.\(bundleIdSuffix).tests",
        deploymentTargets: deployment,
        sources: sources,
        dependencies: dependencies,
    )
}

/// A shared scheme that builds and tests a single unit-test bundle.
func testScheme(name: String) -> Scheme {
    .scheme(
        name: name,
        shared: true,
        buildAction: .buildAction(targets: ["\(name)"]),
        testAction: .targets(["\(name)"]),
    )
}

let project = Project(
    name: "Stuff",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en",
    ),
    packages: [stuffPackage],
    settings: projectSettings,
    targets: [
        .target(
            name: "Where",
            destinations: destinations,
            product: .app,
            bundleId: "com.stuff.where",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "UIApplicationSupportsIndirectInputEvents": .boolean(true),
                "NSLocationWhenInUseUsageDescription": .string(
                    "Where uses your location to figure out which region you're in.",
                ),
                "NSLocationAlwaysAndWhenInUseUsageDescription": .string(
                    "Where checks your location in the background so it can log which region you're in each day.",
                ),
            ]),
            sources: ["Where/Where/Sources/**"],
            resources: ["Where/Where/Resources/**"],
            entitlements: whereAppGroupEntitlements,
            dependencies: [
                .package(product: "LifecycleKit"),
                .package(product: "RegionKit"),
                .package(product: "WhereCore"),
                .package(product: "WhereUI"),
                .package(product: "WhereIntents"),
                .target(name: "WhereWidgets"),
                .target(name: "WhereShareExtension"),
            ],
            // Compile every `*.appiconset` in `AppIcon.xcassets` into the build and
            // auto-write the `CFBundleAlternateIcons` plist entries, so the asset
            // catalog itself is the source of truth for which alternate icons exist
            // (the `./icons` script just adds/removes sets — no names list to keep
            // in sync here). The primary stays `AppIcon`. Where ships no custom
            // global accent color (it tints per-region in SwiftUI), so clear the
            // name actool otherwise looks for — an unset `AccentColor` warns.
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "YES",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
            ]),
        ),
        .target(
            name: "WhereWidgets",
            destinations: destinations,
            product: .appExtension,
            bundleId: "com.stuff.where.widgets",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": .string("Where"),
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": .string("com.apple.widgetkit-extension"),
                ]),
            ]),
            sources: ["Where/WhereWidgets/Sources/**"],
            resources: ["Where/WhereWidgets/Resources/**"],
            entitlements: whereAppGroupEntitlements,
            dependencies: [
                .package(product: "PeriscopeCore"),
                .package(product: "RegionKit"),
                .package(product: "WhereCore"),
                .package(product: "WhereUI"),
            ],
        ),
        .target(
            name: "WhereShareExtension",
            destinations: destinations,
            product: .appExtension,
            bundleId: "com.stuff.where.share",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": .string("Where"),
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": .string("com.apple.share-services"),
                    "NSExtensionPrincipalClass": .string(
                        "$(PRODUCT_MODULE_NAME).ShareViewController",
                    ),
                    // Offer the share action for the content Where can back a
                    // day-count claim with: images, files (PDFs, `.pkpass`
                    // tickets, `.eml` emails), plain text, and web URLs.
                    "NSExtensionAttributes": .dictionary([
                        "NSExtensionActivationRule": .dictionary([
                            "NSExtensionActivationSupportsImageWithMaxCount": .integer(20),
                            "NSExtensionActivationSupportsFileWithMaxCount": .integer(20),
                            "NSExtensionActivationSupportsText": .boolean(true),
                            "NSExtensionActivationSupportsWebURLWithMaxCount": .integer(20),
                        ]),
                    ]),
                ]),
            ]),
            sources: ["Where/WhereShareExtension/Sources/**"],
            resources: ["Where/WhereShareExtension/Resources/**"],
            entitlements: whereAppGroupEntitlements,
            dependencies: [
                .package(product: "PeriscopeCore"),
                .package(product: "WhereCore"),
                .package(product: "WhereUI"),
            ],
        ),
        .target(
            name: "RegionViewer",
            // The first (and only) target to opt into Mac Catalyst: a thin
            // standalone host for the WhereUI `RegionMapView` developer tool.
            // The shared `destinations` constant stays iPhone/iPad-only for
            // everything else.
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .app,
            bundleId: "com.stuff.regionviewer",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "UIApplicationSupportsIndirectInputEvents": .boolean(true),
            ]),
            sources: ["Where/RegionViewer/Sources/**"],
            resources: ["Where/RegionViewer/Resources/**"],
            // No App Group entitlement — the viewer only reads bundled GeoJSON
            // (embedded via the RegionKit dependency), never the app's store.
            dependencies: [
                .package(product: "RegionKit"),
                .package(product: "WhereCore"),
                .package(product: "WhereUI"),
            ],
            // This developer tool ships no custom app icon or accent color, so
            // clear the names the asset-catalog compiler otherwise requires
            // (its `Resources/Assets.xcassets` is intentionally empty).
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
            ]),
        ),
        .target(
            name: "WhereTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "com.stuff.where.tests",
            deploymentTargets: deployment,
            sources: ["Where/Where/Tests/**"],
            dependencies: [
                .target(name: "Where"),
                .package(product: "LifecycleKit"),
                .package(product: "TestHostSupport"),
                .package(product: "WhereUI"),
            ],
        ),
        .target(
            name: "StuffTestHost",
            destinations: destinations,
            product: .app,
            bundleId: "com.stuff.stufftesthost",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "UIApplicationSceneManifest": .dictionary([
                    "UIApplicationSupportsMultipleScenes": .boolean(false),
                    "UISceneConfigurations": .dictionary([
                        "UIWindowSceneSessionRoleApplication": .array([
                            .dictionary([
                                "UISceneConfigurationName": .string("Default Configuration"),
                                "UISceneDelegateClassName": .string(
                                    "$(PRODUCT_MODULE_NAME).SceneDelegate",
                                ),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            sources: ["Shared/StuffTestHost/Sources/**"],
            // Hosted Swift Testing bundles run inside StuffTestHost, so a package's
            // `Bundle.module` resolves against the host app's main bundle at runtime.
            // WhereCore is load-bearing here: depending on it embeds
            // `Stuff_WhereCore.bundle` (its SwiftData schema/resources) and — because
            // WhereCore depends on RegionKit — the GeoJSON `Stuff_RegionKit.bundle`
            // into the host, so code the tests touch (e.g. `RegionAttributor.shared`,
            // the live SwiftData store) finds its resources instead of trapping in the
            // `Bundle.module` accessor. Verified load-bearing: dropping it fails
            // WhereUITests' StringsTests + SwiftDataInspectorWiringTests. RegionKit
            // itself needs no separate entry — WhereCore carries it in (also verified
            // by running the full scheme without a direct RegionKit dep).
            dependencies: [
                .package(product: "WhereCore"),
                // Lets `SceneDelegate` stamp its window with `isMainTestHostWindow`
                // so hosted tests can find it via `TestHostSupport.hostKeyWindow()`.
                .package(product: "TestHostSupport"),
            ],
        ),
        unitTests(
            name: "StuffCoreTests",
            bundleIdSuffix: "stuffcore",
            productDependency: "StuffCore",
            sources: ["Shared/StuffCore/Tests/**"],
        ),
        unitTests(
            name: "LifecycleKitTests",
            bundleIdSuffix: "lifecyclekit",
            productDependency: "LifecycleKit",
            sources: ["Shared/LifecycleKit/Tests/**"],
        ),
        unitTests(
            name: "JournalKitTests",
            bundleIdSuffix: "journalkit",
            productDependency: "JournalKit",
            sources: ["Shared/JournalKit/Tests/**"],
        ),
        unitTests(
            name: "PeriscopeCoreTests",
            bundleIdSuffix: "periscopecore",
            productDependency: "PeriscopeCore",
            sources: ["Shared/Periscope/PeriscopeCore/Tests/**"],
            extraPackageProducts: ["JournalKit"],
        ),
        unitTests(
            name: "PeriscopeUITests",
            bundleIdSuffix: "periscopeui",
            productDependency: "PeriscopeUI",
            sources: ["Shared/Periscope/PeriscopeUI/Tests/**"],
            extraPackageProducts: ["PeriscopeCore"],
        ),
        unitTests(
            name: "PeriscopeToolsTests",
            bundleIdSuffix: "periscopetools",
            productDependency: "PeriscopeTools",
            sources: ["Shared/Periscope/PeriscopeTools/Tests/**"],
            extraPackageProducts: [
                "PeriscopeCore",
                "PeriscopeUI",
            ],
        ),
        unitTests(
            name: "SwiftDataInspectorTests",
            bundleIdSuffix: "swiftdatainspector",
            productDependency: "SwiftDataInspector",
            sources: ["Shared/SwiftDataInspector/Tests/**"],
        ),
        unitTests(
            name: "RegionKitTests",
            bundleIdSuffix: "regionkit",
            productDependency: "RegionKit",
            sources: ["Where/RegionKit/Tests/**"],
        ),
        unitTests(
            name: "WhereCoreTests",
            bundleIdSuffix: "wherecore",
            productDependency: "WhereCore",
            sources: ["Where/WhereCore/Tests/**"],
            extraPackageProducts: ["RegionKit"],
        ),
        // WhereUITests deliberately lists no `extraPackageProducts`. WhereUI is a
        // dynamic framework that statically embeds its own dependencies, so any
        // product *also* linked here would land a second copy in this bundle;
        // with several .xctest bundles loaded into one StuffTestHost that
        // duplicates the module's type metadata, and any type-keyed lookup
        // crossing the WhereUI boundary (SwiftUI `EnvironmentKey`s,
        // `UITraitBridgedEnvironmentKey` bridging, the type-keyed
        // BTraits/BThemes/BStylesheets containers) then silently resolves against
        // the wrong copy — the writer stores under one copy's key type, the
        // reader looks it up under another's. Everything the tests need
        // (BroadwayCore/BroadwayUI, LifecycleKit, PeriscopeCore/UI/Tools,
        // SwiftDataInspector, RegionKit + its GeoJSON bundle) is reached
        // transitively through WhereUI.
        // See the root AGENTS.md "Targets" note.
        unitTests(
            name: "WhereUITests",
            bundleIdSuffix: "whereui",
            productDependency: "WhereUI",
            sources: ["Where/WhereUI/Tests/**"],
        ),
        // WhereIntents depends on WhereUI (a dynamic framework) for its snippet
        // cards, so — exactly like WhereUITests above — this bundle lists no
        // `extraPackageProducts`: WhereUI/WhereCore/RegionKit/Broadway all arrive
        // transitively, and re-listing any of them would land a duplicate copy
        // that splits the module's type metadata across the WhereUI boundary.
        // See the root AGENTS.md "Targets" note.
        unitTests(
            name: "WhereIntentsTests",
            bundleIdSuffix: "whereintents",
            productDependency: "WhereIntents",
            sources: ["Where/WhereIntents/Tests/**"],
        ),
        .target(
            name: "BroadwayCatalog",
            destinations: destinations,
            product: .app,
            bundleId: "com.stuff.broadway.catalog",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "UIApplicationSupportsIndirectInputEvents": .boolean(true),
            ]),
            sources: ["Shared/Broadway/BroadwayCatalog/Sources/**"],
            resources: ["Shared/Broadway/BroadwayCatalog/Resources/**"],
            dependencies: [
                .package(product: "BroadwayUI"),
            ],
        ),
        .target(
            name: "BroadwayCatalogTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "com.stuff.broadway.catalog.tests",
            deploymentTargets: deployment,
            sources: ["Shared/Broadway/BroadwayCatalog/Tests/**"],
            dependencies: [
                .target(name: "BroadwayCatalog"),
                .package(product: "TestHostSupport"),
            ],
        ),
        unitTests(
            name: "BroadwayCoreTests",
            bundleIdSuffix: "broadway.core",
            productDependency: "BroadwayCore",
            sources: ["Shared/Broadway/BroadwayCore/Tests/**"],
        ),
        unitTests(
            name: "BroadwayUITests",
            bundleIdSuffix: "broadway.ui",
            productDependency: "BroadwayUI",
            sources: ["Shared/Broadway/BroadwayUI/Tests/**"],
            extraPackageProducts: [
                "BroadwayCore",
            ],
        ),
        unitTests(
            name: "PortholeCoreTests",
            bundleIdSuffix: "porthole.core",
            productDependency: "PortholeCore",
            sources: ["Shared/Porthole/PortholeCore/Tests/**"],
        ),
        unitTests(
            name: "PortholeKitTests",
            bundleIdSuffix: "porthole.kit",
            productDependency: "PortholeKit",
            sources: ["Shared/Porthole/PortholeKit/Tests/**"],
            extraPackageProducts: ["PortholeCore"],
        ),
        unitTests(
            name: "PortholeClientKitTests",
            bundleIdSuffix: "porthole.client",
            productDependency: "PortholeClientKit",
            sources: ["Shared/Porthole/PortholeClientKit/Tests/**"],
            extraPackageProducts: ["PortholeCore", "PortholeKit"],
        ),
        unitTests(
            name: "PortholeMCPTests",
            bundleIdSuffix: "porthole.mcp",
            productDependency: "PortholeMCP",
            sources: ["Shared/Porthole/PortholeMCP/Tests/**"],
            extraPackageProducts: ["PortholeClientKit", "PortholeCore"],
        ),
        unitTests(
            name: "PortholeCLICoreTests",
            bundleIdSuffix: "porthole.cli",
            productDependency: "PortholeCLICore",
            sources: ["Shared/Porthole/PortholeCLICore/Tests/**"],
            extraPackageProducts: ["PortholeClientKit", "PortholeCore"],
        ),
        .target(
            name: "PortholeCLI",
            destinations: [.mac],
            product: .commandLineTool,
            productName: "porthole",
            bundleId: "com.stuff.porthole.cli",
            deploymentTargets: .macOS("26.0"),
            sources: ["Shared/Porthole/PortholeCLI/Sources/**"],
            dependencies: [
                .package(product: "PortholeCLICore"),
            ],
        ),
    ],
    // Tuist's autogeneration doesn't emit working standalone test actions for
    // these unit-test bundles (only the aggregate `Stuff-Workspace` scheme
    // runs them), so declare them explicitly. This lets `tuist test
    // WhereCoreTests` / `tuist test WhereTests` / `tuist test WhereUITests`
    // target a single bundle without building the whole workspace.
    schemes: [
        // App target schemes are normally autogenerated, but declare the
        // RegionViewer one explicitly so `tuist build RegionViewer` (and a
        // Run that launches the Catalyst app) is always available.
        .scheme(
            name: "RegionViewer",
            shared: true,
            buildAction: .buildAction(targets: ["RegionViewer"]),
            runAction: .runAction(executable: "RegionViewer"),
        ),
        // CI scheme. Rather than the autogenerated `Stuff-Workspace` scheme,
        // CI drives this explicit aggregate of every buildable/testable target
        // (see .github/workflows/ci.yml).
        .scheme(
            name: "Stuff-iOS-Tests",
            shared: true,
            buildAction: .buildAction(targets: [
                "Where",
                "RegionViewer",
                "StuffTestHost",
                "StuffCoreTests",
                "LifecycleKitTests",
                "JournalKitTests",
                "PeriscopeCoreTests",
                "PeriscopeUITests",
                "PeriscopeToolsTests",
                "SwiftDataInspectorTests",
                "RegionKitTests",
                "WhereCoreTests",
                "WhereTests",
                "WhereUITests",
                "WhereIntentsTests",
                "BroadwayCatalog",
                "BroadwayCoreTests",
                "BroadwayUITests",
                "BroadwayCatalogTests",
                "PortholeCoreTests",
                "PortholeKitTests",
                "PortholeClientKitTests",
                "PortholeMCPTests",
                "PortholeCLICoreTests",
            ]),
            testAction: .targets([
                "StuffCoreTests",
                "LifecycleKitTests",
                "JournalKitTests",
                "PeriscopeCoreTests",
                "PeriscopeUITests",
                "PeriscopeToolsTests",
                "SwiftDataInspectorTests",
                "RegionKitTests",
                "WhereCoreTests",
                "WhereTests",
                "WhereUITests",
                "WhereIntentsTests",
                "BroadwayCoreTests",
                "BroadwayUITests",
                "BroadwayCatalogTests",
                "PortholeCoreTests",
                "PortholeKitTests",
                "PortholeClientKitTests",
                "PortholeMCPTests",
                "PortholeCLICoreTests",
            ]),
        ),
        .scheme(
            name: "PortholeCLI",
            shared: true,
            buildAction: .buildAction(targets: ["PortholeCLI"]),
            runAction: .runAction(executable: "PortholeCLI"),
        ),
        testScheme(name: "StuffCoreTests"),
        testScheme(name: "LifecycleKitTests"),
        testScheme(name: "JournalKitTests"),
        testScheme(name: "PeriscopeCoreTests"),
        testScheme(name: "PeriscopeUITests"),
        testScheme(name: "PeriscopeToolsTests"),
        testScheme(name: "SwiftDataInspectorTests"),
        testScheme(name: "RegionKitTests"),
        testScheme(name: "WhereCoreTests"),
        testScheme(name: "WhereTests"),
        testScheme(name: "WhereUITests"),
        testScheme(name: "WhereIntentsTests"),
        testScheme(name: "BroadwayCoreTests"),
        testScheme(name: "BroadwayUITests"),
        testScheme(name: "BroadwayCatalogTests"),
        testScheme(name: "PortholeCoreTests"),
        testScheme(name: "PortholeKitTests"),
        testScheme(name: "PortholeClientKitTests"),
        testScheme(name: "PortholeMCPTests"),
        testScheme(name: "PortholeCLICoreTests"),
    ],
)
