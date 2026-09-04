import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad]
let deployment: DeploymentTargets = .iOS("26.0")

/// The Ledger menu bar app is the only native-macOS target; everything else
/// stays on the shared iOS destinations above.
let macDeployment: DeploymentTargets = .macOS("26.0")

/// Local Swift package (see root `Package.swift`) for the library products
/// (WhereCore, WhereUI, TestHostSupport, the Broadway modules, …).
private let stuffPackage = Package.local(path: .relativeToRoot("."))
private let sfSafeSymbolsPackage = Package.remote(
    url: "https://github.com/SFSafeSymbols/SFSafeSymbols",
    requirement: .upToNextMajor(from: "7.0.0"),
)

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

/// The app additionally owns the CloudKit container that mirrors its
/// SwiftData store. Extensions deliberately keep the App Group-only
/// entitlement above: they write the shared local store and let the app's
/// CloudKit-backed container publish those changes when it next opens.
let whereAppEntitlements: Entitlements = .dictionary([
    // Xcode replaces this development placeholder with the environment from
    // the selected provisioning profile. Keeping the entitlement in the
    // target is what makes automatic signing request Push Notifications.
    "aps-environment": .string("development"),
    "com.apple.security.application-groups": .array([.string("group.com.stuff.where")]),
    "com.apple.developer.icloud-container-identifiers": .array([
        .string("iCloud.com.stuff.where"),
    ]),
    "com.apple.developer.ubiquity-container-identifiers": .array([
        .string("iCloud.com.stuff.where"),
    ]),
    "com.apple.developer.icloud-services": .array([
        .string("CloudKit"),
        .string("CloudDocuments"),
    ]),
    "com.apple.developer.ubiquity-kvstore-identifier": .string(
        "$(TeamIdentifierPrefix)com.stuff.where",
    ),
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
/// Points SwiftPM's generated `Bundle.module` accessors at the built-products
/// directory, where every package resource bundle lands — set on every test
/// target and test action, hosted or not.
///
/// `PACKAGE_RESOURCE_BUNDLE_PATH` is the accessors' own first candidate
/// (DEBUG-only, which test builds are; see any generated
/// `resource_bundle_accessor.swift`, rdar://107766372). It exists because the
/// default candidates — `Bundle.main` and `Bundle(for: BundleFinder.self)` —
/// assume the class and its resource bundle travel together, and Xcode 27
/// beta 4 broke that assumption for hosted tests: its package linking dedupes
/// a statically-absorbed product's code into the one image that carries it
/// (e.g. WhereCore's classes live only inside `WhereUI.framework`), while the
/// product's resource bundle is still copied into each `.xctest`. The class
/// resolves to the framework, the bundle sits unseen in the test bundle, and
/// the accessor's `fatalError` kills the host (CI run 30484782772).
///
/// The pre-#144 remedy — embedding WhereCore in `StuffTestHost` so
/// `Bundle.main` resolves — can't come back: under beta 4 a package product
/// consumed by both the host and the bundles loses its String Catalog
/// generate-symbols step and the build fails. The env override sidesteps
/// linking entirely; simulator processes read host paths, so the
/// built-products directory is always reachable. Remove this only when a
/// later Xcode makes the default candidates resolve for hosted tests again —
/// prove it by deleting the variable and running the full `Stuff-iOS-Tests`
/// scheme on the Xcode CI uses.
let packageResourceEnvironment: [String: EnvironmentVariable] = [
    "PACKAGE_RESOURCE_BUNDLE_PATH": "$(BUILT_PRODUCTS_DIR)",
]

let snapshotEnvironment: [String: EnvironmentVariable] =
    packageResourceEnvironment.merging([
        "SNAPSHOT_EXPECTED_SIMULATOR_RUNTIME_VERSION": "27.0",
        "SNAPSHOT_EXPECTED_SCREEN_SCALE": "3",
        "SNAPSHOT_EXPECTED_TIMEZONE": "America/Los_Angeles",
        "TZ": "America/Los_Angeles",
    ]) { _, new in new }

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
        environmentVariables: packageResourceEnvironment
            .merging(environmentVariables) { _, new in new },
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
            arguments: .arguments(
                environmentVariables: packageResourceEnvironment
                    .merging(testEnvironmentVariables) { _, new in new },
            ),
        ),
    )
}

let project = Project(
    name: "Stuff",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en",
    ),
    packages: [stuffPackage, sfSafeSymbolsPackage],
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
                "UIBackgroundModes": .array([
                    .string("remote-notification"),
                    .string("processing"),
                ]),
                "BGTaskSchedulerPermittedIdentifiers": .array([
                    .string("com.stuff.where.automatic-backup"),
                ]),
                "NSUbiquitousContainers": .dictionary([
                    "iCloud.com.stuff.where": .dictionary([
                        "NSUbiquitousContainerIsDocumentScopePublic": .boolean(true),
                        "NSUbiquitousContainerName": .string("Where"),
                        "NSUbiquitousContainerSupportedFolderLevels": .string("Any"),
                    ]),
                ]),
                "UTExportedTypeDeclarations": .array([
                    .dictionary([
                        "UTTypeConformsTo": .array([.string("public.zip-archive")]),
                        "UTTypeDescription": .string("Where Encrypted Backup"),
                        "UTTypeIdentifier": .string("com.stuff.where.encrypted-backup"),
                        "UTTypeTagSpecification": .dictionary([
                            "public.filename-extension": .array([.string("wherebackup")]),
                        ]),
                    ]),
                ]),
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
            entitlements: whereAppEntitlements,
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
                .package(product: "WhereCrashReporting"),
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
                .package(product: "SFSafeSymbols"),
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
            name: "Ledger",
            destinations: [.mac],
            product: .app,
            bundleId: "com.stuff.ledger",
            deploymentTargets: macDeployment,
            // Full custom plist (not `.extendingDefault`) so the macOS defaults
            // can't sneak in a `NSMainStoryboardFile` — Ledger is a pure
            // SwiftUI/AppKit menu-bar app. `LSUIElement` keeps it out of the
            // Dock and app switcher; it lives in the menu bar only.
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": .string("en"),
                "CFBundleExecutable": .string("$(EXECUTABLE_NAME)"),
                "CFBundleIdentifier": .string("$(PRODUCT_BUNDLE_IDENTIFIER)"),
                "CFBundleInfoDictionaryVersion": .string("6.0"),
                "CFBundleName": .string("$(PRODUCT_NAME)"),
                "CFBundlePackageType": .string("APPL"),
                "CFBundleShortVersionString": .string("1.0"),
                "CFBundleVersion": .string("1"),
                "LSApplicationCategoryType": .string("public.app-category.developer-tools"),
                "LSMinimumSystemVersion": .string("$(MACOSX_DEPLOYMENT_TARGET)"),
                "LSUIElement": .boolean(true),
                "NSPrincipalClass": .string("NSApplication"),
            ]),
            sources: ["Ledger/Ledger/Sources/**"],
            dependencies: [
                .package(product: "LedgerCore"),
                .package(product: "SFSafeSymbols"),
            ],
            // Ledger ships no asset catalog (menu-bar icon is an SF Symbol), so
            // clear the asset-catalog name settings the compiler otherwise
            // looks for.
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
            ]),
        ),
        .target(
            name: "LedgerCoreTests",
            // Hostless macOS unit tests — the `unitTests` helper above is
            // iOS-only (it hosts bundles in StuffTestHost), so this target is
            // declared directly.
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.stuff.ledgercore.tests",
            deploymentTargets: macDeployment,
            sources: ["Ledger/LedgerCore/Tests/**"],
            dependencies: [
                .package(product: "LedgerCore"),
            ],
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
            environmentVariables: packageResourceEnvironment,
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
            // Hosted bundles' `Bundle.module` lookups do *not* resolve against
            // this host: `packageResourceEnvironment` points the generated
            // accessors at the built-products directory instead. Don't re-add a
            // product here to fix a missing-resource failure. The host once
            // embedded WhereCore for exactly that (removed in #144 as redundant
            // on Xcode 27 beta 3), and when beta 4 broke resource resolution the
            // embed could not come back: under beta 4 a package product consumed
            // by both this host and the test bundles loses its String Catalog
            // generate-symbols step, failing the build (verified with WhereCore
            // and, via LifecycleKitUI, with WhereUI). See the note on
            // `packageResourceEnvironment` for the full story.
            dependencies: [
                // Lets `SceneDelegate` stamp its window with `isMainTestHostWindow`
                // so hosted tests can find it via `TestHostSupport.hostKeyWindow()`.
                .package(product: "TestHostSupport"),
            ],
        ),
        unitTests(
            name: "CreditKitTests",
            bundleIdSuffix: "creditkit",
            productDependency: "CreditKit",
            sources: ["Shared/CreditKit/Tests/**"],
        ),
        unitTests(
            name: "WhereCrashReportingTests",
            bundleIdSuffix: "wherecrashreporting",
            productDependency: "WhereCrashReporting",
            sources: ["Where/WhereCrashReporting/Tests/**"],
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
            name: "KeychainKitTests",
            bundleIdSuffix: "keychainkit",
            productDependency: "KeychainKit",
            sources: ["Shared/KeychainKit/Tests/**"],
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
            name: "InspectorTests",
            bundleIdSuffix: "inspector",
            productDependency: "Inspector",
            sources: ["Shared/Inspector/Tests/**"],
        ),
        unitTests(
            name: "FlyoverTests",
            bundleIdSuffix: "flyover",
            productDependency: "Flyover",
            sources: ["Shared/Flyover/Tests/**"],
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
            extraPackageProducts: ["SFSafeSymbols"],
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
        // WhereUITests names LifecycleKit and SFSafeSymbols because its test sources
        // exercise those public types directly. Xcode 27 emits WhereUI as a dynamic package
        // products in this graph, so merely copying WhereUI's transitive frameworks
        // does not add them to the test bundle's link command. Everything else arrives
        // through WhereUI; re-listing a statically absorbed product can still split
        // type-keyed lookups in the full multi-bundle scheme.
        // Guard: WhereStylesheetTests.resolvesTraitAwareTokensFromTheBroadwayRoot.
        // See "Never double-link a product WhereUI already carries" in the root
        // AGENTS.md; mechanism: PR #145.
        unitTests(
            name: "WhereUITests",
            bundleIdSuffix: "whereui",
            productDependency: "WhereUI",
            sources: ["Where/WhereUI/Tests/**"],
            extraPackageProducts: ["LifecycleKit", "SFSafeSymbols"],
        ),
        // WhereIntents depends on WhereUI for its snippet cards, so — exactly like
        // WhereUITests above — this bundle lists no `extraPackageProducts`:
        // WhereUI/WhereCore/RegionKit/Broadway all arrive transitively, and
        // re-listing any of them would land a duplicate copy in this image.
        // See "Never double-link a product WhereUI already carries" in the root
        // AGENTS.md.
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
        // Periscope and Inspector suites don't build against WhereUI
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
        // process across bundles, re-measure before adding another.
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
            name: "FlyoverSnapshotTests",
            bundleIdSuffix: "flyover.snapshot",
            productDependency: "Flyover",
            sources: ["Shared/Flyover/SnapshotTests/**"],
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
            name: "InspectorSnapshotTests",
            bundleIdSuffix: "inspector.snapshot",
            productDependency: "Inspector",
            sources: ["Shared/Inspector/SnapshotTests/**"],
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
                .package(product: "SFSafeSymbols"),
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
        .scheme(
            name: "Ledger",
            shared: true,
            buildAction: .buildAction(targets: ["Ledger"]),
            runAction: .runAction(executable: "Ledger"),
        ),
        // The workspace mixes iOS targets and the macOS-only Ledger targets, so
        // CI drives two platform-scoped schemes — no single xcodebuild
        // destination can build both. The macOS-only Ledger scheme runs in its
        // own `test-macos` CI job (see .github/workflows/ci.yml).
        .scheme(
            name: "Ledger-macOS-Tests",
            shared: true,
            buildAction: .buildAction(targets: ["Ledger", "LedgerCoreTests"]),
            testAction: .targets(["LedgerCoreTests"]),
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
                "CreditKitTests",
                "WhereCrashReportingTests",
                "LifecycleKitTests",
                "LifecycleKitUITests",
                "JournalKitTests",
                "KeychainKitTests",
                "PeriscopeCoreTests",
                "PeriscopeUITests",
                "PeriscopeToolsTests",
                "InspectorTests",
                "FlyoverTests",
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
            testAction: .targets(
                [
                    "CreditKitTests",
                    "WhereCrashReportingTests",
                    "LifecycleKitTests",
                    "LifecycleKitUITests",
                    "JournalKitTests",
                    "KeychainKitTests",
                    "PeriscopeCoreTests",
                    "PeriscopeUITests",
                    "PeriscopeToolsTests",
                    "InspectorTests",
                    "FlyoverTests",
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
                ],
                arguments: .arguments(environmentVariables: packageResourceEnvironment),
            ),
        ),
        testScheme(name: "LedgerCoreTests"),
        testScheme(name: "CreditKitTests"),
        testScheme(name: "WhereCrashReportingTests"),
        testScheme(name: "LifecycleKitTests"),
        testScheme(name: "LifecycleKitUITests"),
        testScheme(name: "JournalKitTests"),
        testScheme(name: "KeychainKitTests"),
        testScheme(name: "PeriscopeCoreTests"),
        testScheme(name: "PeriscopeUITests"),
        testScheme(name: "PeriscopeToolsTests"),
        testScheme(name: "InspectorTests"),
        testScheme(name: "FlyoverTests"),
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
                "FlyoverSnapshotTests",
                "PeriscopeToolsSnapshotTests",
                "InspectorSnapshotTests",
            ]),
            testAction: .targets(
                [
                    "WhereUISnapshotTests",
                    "FlyoverSnapshotTests",
                    "PeriscopeToolsSnapshotTests",
                    "InspectorSnapshotTests",
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
