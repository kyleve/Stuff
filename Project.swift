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

/// Base build settings applied to every Tuist-generated target.
///
/// `STRING_CATALOG_GENERATE_SYMBOLS` turns on Xcode's type-safe String Catalog
/// symbol generation for the app and app-extension targets (Where, WhereWidgets,
/// WhereShareExtension, …). The SwiftPM package targets declared in `Package.swift`
/// (WhereUI, WhereCore, RegionKit, LifecycleKitUI) get symbol generation
/// automatically from the toolchain, so this only needs to reach the
/// Tuist-native targets.
///
/// `DEVELOPMENT_TEAM` is threaded in from the environment when present (see above).
private let projectSettings: Settings = .settings(
    base: developmentTeam.isEmpty
        ? ["STRING_CATALOG_GENERATE_SYMBOLS": "YES"]
        : [
            "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
            "DEVELOPMENT_TEAM": .string(developmentTeam),
        ],
)

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
/// `testEnvironmentVariables` are set on the test action, so they reach the
/// test process (schemes without any keep an argument-less test action).
func testScheme(
    name: String,
    testEnvironmentVariables: [String: EnvironmentVariable] = [:],
) -> Scheme {
    .scheme(
        name: name,
        shared: true,
        buildAction: .buildAction(targets: ["\(name)"]),
        testAction: .targets(
            ["\(name)"],
            arguments: testEnvironmentVariables.isEmpty
                ? nil
                : .arguments(environmentVariables: testEnvironmentVariables),
        ),
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
            // Keep this host thin — it deliberately depends on nothing but
            // TestHostSupport.
            //
            // It used to also depend on WhereCore, to embed `Stuff_WhereCore.bundle`
            // and (transitively) the GeoJSON `Stuff_RegionKit.bundle` into the host,
            // on the theory that a hosted bundle's `Bundle.module` resolves against
            // the host's main bundle. That is no longer true, and on Xcode 27 it is
            // no longer needed: each `.xctest` now carries its own copies of the
            // resource bundles for the code it links (`WhereUITests.xctest` ships
            // `Stuff_WhereCore.bundle`, `Stuff_RegionKit.bundle`,
            // `Stuff_WhereUI.bundle`, `Stuff_LifecycleKitUI.bundle`), so SwiftPM's
            // `Bundle.module` finds them via `Bundle(for: BundleFinder.self)` — the
            // test bundle — and never falls back to `Bundle.main`. Verified by
            // removing the dependency and running the full `Stuff-iOS-Tests` and
            // image-snapshot schemes green, with the built host confirmed to contain
            // no WhereCore symbols and no resource bundles at all. (One of the two
            // canaries the old note cited as proof, `WhereUITests.StringsTests`, had
            // also ceased to exist with the String Catalog symbol migration.)
            //
            // Don't re-add a product here to fix a missing-resource failure: that
            // makes every unrelated bundle in the scheme pay for it, and duplicates
            // the payload (the whole GeoJSON set was being embedded twice). Give the
            // bundle that needs the resource a dependency on the product that owns
            // it instead.
            dependencies: [
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
            name: "LifecycleKitUITests",
            bundleIdSuffix: "lifecyclekitui",
            productDependency: "LifecycleKitUI",
            sources: ["Shared/LifecycleKitUI/Tests/**"],
            extraPackageProducts: ["LifecycleKit"],
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
            name: "SnapshotKitTests",
            bundleIdSuffix: "snapshotkit",
            productDependency: "SnapshotKit",
            sources: ["Shared/SnapshotKit/Tests/**"],
        ),
        // The capture/compare pipeline's own regression tests. They render
        // through `renderSnapshotImage` (so they need the `StuffTestHost` key
        // window) but assert on probed pixels rather than LFS reference images,
        // so — unlike `StuffSnapshotTests` — this bundle is fast, has no
        // `__Snapshots__/`, and runs in the main `Stuff-iOS-Tests` scheme /
        // `test` CI job. `SnapshotKitTesting` embeds its dependency closure
        // (SnapshotKit, SnapshotTesting, AccessibilitySnapshot) into the
        // `.xctest`, as every bundle here embeds what it links. That means the
        // `Stuff-iOS-Tests` host process holds a SnapshotKit copy per bundle
        // that links one, but no lookup crosses between them: each bundle's
        // capture writes and reads resolve within its own image.
        unitTests(
            name: "SnapshotKitTestingTests",
            bundleIdSuffix: "snapshotkittesting",
            productDependency: "SnapshotKitTesting",
            sources: ["Shared/SnapshotKitTesting/Tests/**"],
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
        // (BroadwayCore/BroadwayUI, LifecycleKit/LifecycleKitUI, PeriscopeCore/UI/Tools,
        // SwiftDataInspector, RegionKit + its GeoJSON bundle) is reached
        // transitively through WhereUI.
        // See "Never double-link a product a dynamic framework already
        // carries" in the root AGENTS.md.
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
        // See "Never double-link a product a dynamic framework already
        // carries" in the root AGENTS.md.
        unitTests(
            name: "WhereIntentsTests",
            bundleIdSuffix: "whereintents",
            productDependency: "WhereIntents",
            sources: ["Where/WhereIntents/Tests/**"],
        ),
        // Every image snapshot suite in the repo, in ONE bundle. Slow +
        // LFS-backed, so it runs in its own `snapshot` CI job (see
        // .github/workflows/ci.yml) via its own `testScheme` below — it is
        // deliberately NOT in the `Stuff-iOS-Tests` scheme, keeping image
        // snapshots out of the main `test` job.
        //
        // One bundle, not one per module, and that is load-bearing rather than
        // convenience. Every `.xctest` statically embeds what it links, so a
        // second snapshot bundle would carry a second copy of
        // `SnapshotKitTesting` — and its "process-global" capture state is
        // module-global, i.e. per copy: `_swizzleDepth` and the override
        // globals in `SafeAreaInsetsSwizzling.swift`, `SnapshotCaptureLock`,
        // and the `UIView.snapshotKitOverriddenSafeAreaInsets` category. Two
        // copies loaded into one `StuffTestHost` process would each count
        // their own swizzle depth against the one shared `UIView` method
        // exchange (parity flips → captures silently rendering with the
        // simulator's real safe-area insets), and neither copy's capture lock
        // could see the other's captures. Verified with `nm` on the built
        // bundles, which show a private `_swizzleDepth` per `.xctest`. Keeping
        // one bundle keeps one copy, which is what makes those types' "process
        // wide" docs true. Suites still live in — and record their references
        // next to — the module they cover: swift-snapshot-testing derives the
        // `__Snapshots__` directory from the calling file's `#filePath`, which
        // `assertSnapshots` threads through, so per-module ownership needs
        // per-module *source directories*, not per-module bundles.
        //
        // Lists only `SnapshotKitTesting` in `extraPackageProducts`: the
        // test-only capture pipeline, which WhereUI deliberately never links.
        // PeriscopeTools and SwiftDataInspector are NOT listed — they arrive
        // transitively through WhereUI, and re-listing either would land the
        // duplicate copy the root AGENTS.md "Targets" note warns about. Their
        // suites import them anyway, exactly as WhereUITests imports WhereCore
        // and RegionKit without listing them.
        //
        // `SnapshotKitTesting` embeds its dependency closure, SnapshotKit
        // included — which WhereUI carries too — but that does *not* land a
        // second copy here: the linker coalesces them. Verified on the built
        // bundle, which defines exactly one set of SnapshotKit symbols, the
        // same count as WhereUITests (a bundle that links no extra products at
        // all). So `\.isCapturingSnapshot` has no copy boundary to cross.
        // `SnapshotCaptureFlagProbeTests` still pins the path end to end — the
        // pipeline's `traitOverrides` write reaching a WhereUI-defined view's
        // read — so a toolchain that stopped coalescing would fail loudly
        // rather than silently returning defaults.
        unitTests(
            name: "StuffSnapshotTests",
            bundleIdSuffix: "snapshot",
            productDependency: "WhereUI",
            sources: [
                "Where/WhereUI/SnapshotTests/**",
                "Shared/Periscope/PeriscopeTools/SnapshotTests/**",
                "Shared/SwiftDataInspector/SnapshotTests/**",
            ],
            extraPackageProducts: ["SnapshotKitTesting"],
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
                "LifecycleKitUITests",
                "JournalKitTests",
                "PeriscopeCoreTests",
                "PeriscopeUITests",
                "PeriscopeToolsTests",
                "SwiftDataInspectorTests",
                "SnapshotKitTests",
                "SnapshotKitTestingTests",
                "RegionKitTests",
                "WhereCoreTests",
                "WhereTests",
                "WhereUITests",
                "WhereIntentsTests",
                "BroadwayCatalog",
                "BroadwayCoreTests",
                "BroadwayUITests",
                "BroadwayCatalogTests",
            ]),
            testAction: .targets([
                "StuffCoreTests",
                "LifecycleKitTests",
                "LifecycleKitUITests",
                "JournalKitTests",
                "PeriscopeCoreTests",
                "PeriscopeUITests",
                "PeriscopeToolsTests",
                "SwiftDataInspectorTests",
                "SnapshotKitTests",
                "SnapshotKitTestingTests",
                "RegionKitTests",
                "WhereCoreTests",
                "WhereTests",
                "WhereUITests",
                "WhereIntentsTests",
                "BroadwayCoreTests",
                "BroadwayUITests",
                "BroadwayCatalogTests",
            ]),
        ),
        testScheme(name: "StuffCoreTests"),
        testScheme(name: "LifecycleKitTests"),
        testScheme(name: "LifecycleKitUITests"),
        testScheme(name: "JournalKitTests"),
        testScheme(name: "PeriscopeCoreTests"),
        testScheme(name: "PeriscopeUITests"),
        testScheme(name: "PeriscopeToolsTests"),
        testScheme(name: "SwiftDataInspectorTests"),
        testScheme(name: "SnapshotKitTests"),
        testScheme(name: "SnapshotKitTestingTests"),
        testScheme(name: "RegionKitTests"),
        testScheme(name: "WhereCoreTests"),
        testScheme(name: "WhereTests"),
        testScheme(name: "WhereUITests"),
        // Pins the environment the LFS reference images were recorded on. The
        // `assertSnapshots` runner compares the SNAPSHOT_EXPECTED_* values
        // against the live simulator and fails fast with one clear message on
        // a mismatched runtime, screen scale, or timezone — instead of
        // hundreds of confusing image diffs. TZ pins the test process's
        // timezone itself: several references bake Pacific wall-clock
        // dates/times into the image (widget day labels, log-viewer
        // timestamps), so an unpinned UTC CI runner would shift every
        // date-rendering snapshot. SNAPSHOT_EXPECTED_TIMEZONE is the guard
        // that verifies the TZ pin actually reached the test process.
        testScheme(
            name: "StuffSnapshotTests",
            testEnvironmentVariables: [
                "SNAPSHOT_EXPECTED_SIMULATOR_RUNTIME_VERSION": "27.0",
                "SNAPSHOT_EXPECTED_SCREEN_SCALE": "3",
                "SNAPSHOT_EXPECTED_TIMEZONE": "America/Los_Angeles",
                "TZ": "America/Los_Angeles",
            ],
        ),
        testScheme(name: "WhereIntentsTests"),
        testScheme(name: "BroadwayCoreTests"),
        testScheme(name: "BroadwayUITests"),
        testScheme(name: "BroadwayCatalogTests"),
    ],
)
