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

/// The environment the LFS reference images were recorded on, and the single
/// source of truth for it.
///
/// The `assertSnapshots` runner compares the `SNAPSHOT_EXPECTED_*` values
/// against the live simulator and fails fast with one clear message on a
/// mismatched runtime, screen scale, or timezone — instead of hundreds of
/// confusing image diffs. `TZ` pins the test process's timezone itself: several
/// references bake Pacific wall-clock dates/times into the image (widget day
/// labels, log-viewer timestamps), so an unpinned UTC CI runner would shift
/// every date-rendering snapshot. `SNAPSHOT_EXPECTED_TIMEZONE` is the guard
/// that verifies the `TZ` pin actually reached the test process.
///
/// Set on **both** the snapshot targets and the aggregate scheme below, which
/// is deliberate: Tuist autogenerates a scheme per target, so a target that
/// carries these is correctly pinned when someone runs that one bundle from
/// Xcode, while the aggregate scheme covers the CI invocation. Setting them in
/// only one place leaves the other silently unpinned — and an unpinned run
/// doesn't fail loudly, it just compares against references recorded somewhere
/// else.
let snapshotEnvironment: [String: EnvironmentVariable] = [
    "SNAPSHOT_EXPECTED_SIMULATOR_RUNTIME_VERSION": "27.0",
    "SNAPSHOT_EXPECTED_SCREEN_SCALE": "3",
    "SNAPSHOT_EXPECTED_TIMEZONE": "America/Los_Angeles",
    "TZ": "America/Los_Angeles",
]

func unitTests(
    name: String,
    bundleIdSuffix: String,
    productDependency: String,
    sources: ProjectDescription.SourceFilesList,
    extraPackageProducts: [String] = [],
    environmentVariables: [String: EnvironmentVariable] = [:],
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
        environmentVariables: environmentVariables,
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
                // Stated explicitly rather than left to Tuist's `1.0` / `1`
                // defaults, because Settings > About shows them: the version a
                // user reads off the screen should be one this manifest chose.
                "CFBundleShortVersionString": .string("1.0"),
                "CFBundleVersion": .string("1"),
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
            // Writes `WhereGitSHA` / `WhereGitStatus` into the built Info.plist
            // for Settings > About. A *post* script so it lands after "Process
            // Info.plist" and before signing, and `basedOnDependencyAnalysis:
            // false` so an unchanged source tree still re-stamps a new commit.
            scripts: [
                .post(
                    path: "Where/Where/Scripts/stamp-build-info.sh",
                    name: "Stamp Build Info",
                    basedOnDependencyAnalysis: false,
                ),
            ],
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
            name: "CreditKitTests",
            bundleIdSuffix: "creditkit",
            productDependency: "CreditKit",
            sources: ["Shared/CreditKit/Tests/**"],
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
        // Image snapshot bundles: one per module that owns image references,
        // all gathered into the single `StuffSnapshotTests` scheme below so CI
        // runs them in one `snapshot` job. They are slow and LFS-backed, so
        // they are deliberately NOT in the `Stuff-iOS-Tests` scheme.
        //
        // One bundle per module rather than one shared bundle, because a
        // module's image suite should link only what that module needs: the
        // Periscope and SwiftDataInspector suites don't build against WhereUI
        // at all. Each records its references beside its own sources —
        // swift-snapshot-testing derives the `__Snapshots__` directory from the
        // calling file's `#filePath`, which `assertSnapshots` threads through.
        //
        // Separate bundles are safe here because each `.xctest` gets its own
        // `StuffTestHost` process: measured on Xcode 27 by probing
        // `ProcessInfo.processIdentifier` from two bundles in one scheme, which
        // reported different PIDs on both a filtered and a full unfiltered run.
        // That matters specifically for these bundles, because each statically
        // embeds its own copy of `SnapshotKitTesting`, whose capture state is
        // module-global and therefore per copy (`_swizzleDepth` and the
        // override globals in `SafeAreaInsetsSwizzling.swift`,
        // `SnapshotCaptureLock`, the `UIView` category). Co-loaded into one
        // process those copies would fight over the single `UIView` method
        // exchange; in separate processes each is genuinely process-wide, as
        // its docs claim. If a future toolchain ever starts sharing one host
        // process across bundles, re-measure before adding a fourth.
        //
        // Each lists only `SnapshotKitTesting` in `extraPackageProducts` — the
        // test-only capture pipeline, which no shipping module links. Nothing
        // else is re-listed: whatever the module already carries arrives
        // transitively, per the double-linking rule in the root AGENTS.md.
        // `SnapshotCaptureFlagProbeTests` (in WhereUISnapshotTests) pins the
        // pipeline's `traitOverrides` write reaching a WhereUI-defined view's
        // `\.isCapturingSnapshot` read, so a toolchain that stopped coalescing
        // the two SnapshotKit copies in that bundle would fail loudly rather
        // than silently returning defaults.
        unitTests(
            name: "WhereUISnapshotTests",
            bundleIdSuffix: "whereui.snapshot",
            productDependency: "WhereUI",
            sources: ["Where/WhereUI/SnapshotTests/**"],
            extraPackageProducts: ["SnapshotKitTesting"],
            environmentVariables: snapshotEnvironment,
        ),
        unitTests(
            name: "PeriscopeToolsSnapshotTests",
            bundleIdSuffix: "periscopetools.snapshot",
            productDependency: "PeriscopeTools",
            sources: ["Shared/Periscope/PeriscopeTools/SnapshotTests/**"],
            extraPackageProducts: ["SnapshotKitTesting"],
            environmentVariables: snapshotEnvironment,
        ),
        unitTests(
            name: "SwiftDataInspectorSnapshotTests",
            bundleIdSuffix: "swiftdatainspector.snapshot",
            productDependency: "SwiftDataInspector",
            sources: ["Shared/SwiftDataInspector/SnapshotTests/**"],
            extraPackageProducts: ["SnapshotKitTesting"],
            environmentVariables: snapshotEnvironment,
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
                "CreditKitTests",
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
                "CreditKitTests",
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
        testScheme(name: "CreditKitTests"),
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
        // Every image-snapshot bundle, in one scheme, so CI runs them all in
        // the single `snapshot` job. A new module's image suite gets its own
        // `*SnapshotTests` target above and joins the lists here — it must not
        // get a scheme (or CI job) of its own.
        //
        // The environment pins (see `snapshotEnvironment`) are why this scheme
        // exists rather than folding the bundles into `Stuff-iOS-Tests`. They
        // are also set on each snapshot target, so the per-target schemes
        // Tuist autogenerates are pinned too.
        .scheme(
            name: "StuffSnapshotTests",
            shared: true,
            buildAction: .buildAction(targets: [
                "WhereUISnapshotTests",
                "PeriscopeToolsSnapshotTests",
                "SwiftDataInspectorSnapshotTests",
            ]),
            testAction: .targets(
                [
                    "WhereUISnapshotTests",
                    "PeriscopeToolsSnapshotTests",
                    "SwiftDataInspectorSnapshotTests",
                ],
                arguments: .arguments(environmentVariables: snapshotEnvironment),
            ),
        ),
        testScheme(name: "WhereIntentsTests"),
        testScheme(name: "BroadwayCoreTests"),
        testScheme(name: "BroadwayUITests"),
        testScheme(name: "BroadwayCatalogTests"),
    ],
)
