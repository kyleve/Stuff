import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad]
let deployment: DeploymentTargets = .iOS("26.0")

/// The Foreman menu bar app is the only native-macOS target; everything else
/// stays on the shared iOS destinations above.
let macDeployment: DeploymentTargets = .macOS("26.0")

/// Local Swift package (see root `Package.swift`) for StuffCore, WhereCore, WhereUI, and
/// WhereTesting.
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

/// App Group shared by the Where app and its widget extension so both
/// processes see the same on-disk SwiftData store (see
/// `SwiftDataStore.appGroupIdentifier`, which must match).
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
        .package(product: "WhereTesting"),
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
                .package(product: "LogKit"),
                .package(product: "WhereCore"),
                .package(product: "WhereUI"),
                .target(name: "WhereWidgets"),
            ],
            // Compile every `*.appiconset` in `AppIcon.xcassets` into the build and
            // auto-write the `CFBundleAlternateIcons` plist entries, so the asset
            // catalog itself is the source of truth for which alternate icons exist
            // (the `./icons` script just adds/removes sets — no names list to keep
            // in sync here). The primary stays `AppIcon`.
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "YES",
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
                .package(product: "LogKit"),
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
            // (embedded via the WhereCore dependency), never the app's store.
            dependencies: [
                .package(product: "LogKit"),
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
            name: "Foreman",
            destinations: [.mac],
            product: .app,
            bundleId: "com.stuff.foreman",
            deploymentTargets: macDeployment,
            // Full custom plist (not `.extendingDefault`) so the macOS defaults
            // can't sneak in a `NSMainStoryboardFile` — Foreman is a pure
            // SwiftUI `MenuBarExtra` app. `LSUIElement` keeps it out of the
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
                "LSMinimumSystemVersion": .string("$(MACOSX_DEPLOYMENT_TARGET)"),
                "LSUIElement": .boolean(true),
                "NSPrincipalClass": .string("NSApplication"),
            ]),
            sources: ["Foreman/Foreman/Sources/**"],
            // No Resources folder: the menu bar icon is an SF Symbol and the
            // app ships no asset catalog, so clear the names the asset-catalog
            // compiler would otherwise look for.
            dependencies: [
                .package(product: "ForemanCore"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
            ]),
        ),
        .target(
            name: "ForemanCoreTests",
            // Hostless macOS unit tests — the `unitTests` helper above is
            // iOS-only (it hosts bundles in StuffTestHost), so this target is
            // declared directly.
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.stuff.foremancore.tests",
            deploymentTargets: macDeployment,
            sources: ["Foreman/ForemanCore/Tests/**"],
            dependencies: [
                .package(product: "ForemanCore"),
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
                .package(product: "WhereTesting"),
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
            // Hosted Swift Testing bundles run inside StuffTestHost, so WhereCore's
            // `Bundle.module` resolves against the host app's main bundle at runtime.
            // Depending on WhereCore here makes Tuist embed `Stuff_WhereCore.bundle`
            // (its GeoJSON region data) into the host, so code the tests touch — e.g.
            // the lazy `RegionAttributor.shared` — finds its resources instead of
            // trapping in the `Bundle.module` accessor.
            dependencies: [
                .package(product: "WhereCore"),
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
            name: "LogKitTests",
            bundleIdSuffix: "logkit",
            productDependency: "LogKit",
            sources: ["Shared/LogKit/Tests/**"],
        ),
        unitTests(
            name: "LogViewerUITests",
            bundleIdSuffix: "logviewerui",
            productDependency: "LogViewerUI",
            sources: ["Shared/LogViewerUI/Tests/**"],
        ),
        unitTests(
            name: "SwiftDataInspectorTests",
            bundleIdSuffix: "swiftdatainspector",
            productDependency: "SwiftDataInspector",
            sources: ["Shared/SwiftDataInspector/Tests/**"],
        ),
        unitTests(
            name: "WhereCoreTests",
            bundleIdSuffix: "wherecore",
            productDependency: "WhereCore",
            sources: ["Where/WhereCore/Tests/**"],
        ),
        unitTests(
            name: "WhereUITests",
            bundleIdSuffix: "whereui",
            productDependency: "WhereUI",
            sources: ["Where/WhereUI/Tests/**"],
            extraPackageProducts: ["LifecycleKit", "LogViewerUI", "SwiftDataInspector"],
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
        // CI schemes. The autogenerated `Stuff-Workspace` scheme mixes iOS and
        // macOS targets, which no single xcodebuild destination can build, so
        // CI drives these two platform-scoped aggregates instead (see
        // .github/workflows/ci.yml).
        .scheme(
            name: "Stuff-iOS-Tests",
            shared: true,
            buildAction: .buildAction(targets: [
                "Where",
                "RegionViewer",
                "StuffTestHost",
                "StuffCoreTests",
                "LifecycleKitTests",
                "LogKitTests",
                "LogViewerUITests",
                "SwiftDataInspectorTests",
                "WhereCoreTests",
                "WhereTests",
                "WhereUITests",
            ]),
            testAction: .targets([
                "StuffCoreTests",
                "LifecycleKitTests",
                "LogKitTests",
                "LogViewerUITests",
                "SwiftDataInspectorTests",
                "WhereCoreTests",
                "WhereTests",
                "WhereUITests",
            ]),
        ),
        .scheme(
            name: "Foreman-macOS-Tests",
            shared: true,
            buildAction: .buildAction(targets: ["Foreman", "ForemanCoreTests"]),
            testAction: .targets(["ForemanCoreTests"]),
        ),
        testScheme(name: "ForemanCoreTests"),
        testScheme(name: "StuffCoreTests"),
        testScheme(name: "LifecycleKitTests"),
        testScheme(name: "LogKitTests"),
        testScheme(name: "LogViewerUITests"),
        testScheme(name: "SwiftDataInspectorTests"),
        testScheme(name: "WhereCoreTests"),
        testScheme(name: "WhereTests"),
        testScheme(name: "WhereUITests"),
    ],
)
