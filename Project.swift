import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad]
let deployment: DeploymentTargets = .iOS("26.0")

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
                .package(product: "WhereUI"),
                .target(name: "WhereWidgets"),
            ],
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
            entitlements: whereAppGroupEntitlements,
            dependencies: [
                .package(product: "WhereCore"),
                .package(product: "WhereUI"),
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
                .package(product: "WhereTesting"),
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
            dependencies: [],
        ),
        unitTests(
            name: "StuffCoreTests",
            bundleIdSuffix: "stuffcore",
            productDependency: "StuffCore",
            sources: ["Shared/StuffCore/Tests/**"],
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
        ),
    ],
    // Tuist's autogeneration doesn't emit working standalone test actions for
    // these unit-test bundles (only the aggregate `Stuff-Workspace` scheme
    // runs them), so declare them explicitly. This lets `tuist test
    // WhereCoreTests` / `tuist test WhereTests` / `tuist test WhereUITests`
    // target a single bundle without building the whole workspace.
    schemes: [
        testScheme(name: "WhereCoreTests"),
        testScheme(name: "WhereTests"),
        testScheme(name: "WhereUITests"),
    ],
)
