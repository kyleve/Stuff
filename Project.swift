import ProjectDescription

let macDestinations: Destinations = [.mac]
let macDeployment: DeploymentTargets = .macOS("26.0")

/// No `.macCatalyst` here: it pulls iOS targets into macOS `tuist test` runs and breaks signing without a dev team.
let iosDestinations: Destinations = [.iPhone, .iPad]
let iosDeployment: DeploymentTargets = .iOS("26.0")

func framework(
    _ name: String,
    bundleIdSuffix: String,
    pathPrefix: String? = nil,
    dependencies: [TargetDependency] = [],
) -> [Target] {
    let base = pathPrefix.map { "\($0)/\(name)" } ?? name
    return [
        .target(
            name: name,
            destinations: macDestinations,
            product: .framework,
            bundleId: "com.stuff.\(bundleIdSuffix)",
            deploymentTargets: macDeployment,
            sources: ["\(base)/Sources/**"],
            dependencies: dependencies,
        ),
        .target(
            name: "\(name)Tests",
            destinations: macDestinations,
            product: .unitTests,
            bundleId: "com.stuff.\(bundleIdSuffix).tests",
            deploymentTargets: macDeployment,
            sources: ["\(base)/Tests/**"],
            dependencies: [.target(name: name)],
        ),
    ]
}

func macApp(
    _ name: String,
    bundleIdSuffix: String,
    infoPlist: [String: Plist.Value] = [:],
    dependencies: [TargetDependency] = [],
) -> [Target] {
    [
        .target(
            name: name,
            destinations: macDestinations,
            product: .app,
            bundleId: "com.stuff.\(bundleIdSuffix)",
            deploymentTargets: macDeployment,
            infoPlist: .extendingDefault(with: infoPlist),
            sources: ["\(name)/Sources/**"],
            resources: ["\(name)/Resources/**"],
            dependencies: dependencies,
        ),
        .target(
            name: "\(name)Tests",
            destinations: macDestinations,
            product: .unitTests,
            bundleId: "com.stuff.\(bundleIdSuffix).tests",
            deploymentTargets: macDeployment,
            sources: ["\(name)/Tests/**"],
            dependencies: [.target(name: name)],
        ),
    ]
}

func iosFramework(
    _ name: String,
    bundleIdSuffix: String,
    dependencies: [TargetDependency] = [],
) -> Target {
    .target(
        name: name,
        destinations: iosDestinations,
        product: .framework,
        bundleId: "com.stuff.\(bundleIdSuffix)",
        deploymentTargets: iosDeployment,
        sources: ["Where/\(name)/Sources/**"],
        dependencies: dependencies,
    )
}

func hostedIOSUnitTests(
    moduleName: String,
    bundleIdSuffix: String,
    sourcesRoot: String,
) -> Target {
    .target(
        name: "\(moduleName)Tests",
        destinations: iosDestinations,
        product: .unitTests,
        bundleId: "com.stuff.\(bundleIdSuffix).tests",
        deploymentTargets: iosDeployment,
        sources: ["\(sourcesRoot)/\(moduleName)/Tests/**"],
        dependencies: [
            .target(name: moduleName),
            .target(name: "WhereTesting"),
            .target(name: "StuffTestHost"),
        ],
    )
}

let project = Project(
    name: "Stuff",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en",
    ),
    targets: [
        .target(
            name: "StuffCore",
            destinations: iosDestinations,
            product: .framework,
            bundleId: "com.stuff.stuffcore",
            deploymentTargets: iosDeployment,
            sources: ["Shared/StuffCore/Sources/**"],
            dependencies: [],
        ),
        .target(
            name: "StuffTestHost",
            destinations: iosDestinations,
            product: .app,
            bundleId: "com.stuff.stufftesthost",
            deploymentTargets: iosDeployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "UIApplicationSceneManifest": .dictionary([
                    "UIApplicationSupportsMultipleScenes": .boolean(false),
                    "UISceneConfigurations": .dictionary([
                        "UIWindowSceneSessionRoleApplication": .array([
                            .dictionary([
                                "UISceneConfigurationName": .string("Default Configuration"),
                                "UISceneDelegateClassName": .string("$(PRODUCT_MODULE_NAME).SceneDelegate"),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            sources: ["Shared/StuffTestHost/Sources/**"],
            dependencies: [],
        ),
        iosFramework("WhereCore", bundleIdSuffix: "wherecore"),
        iosFramework("WhereUI", bundleIdSuffix: "whereui", dependencies: [.target(name: "WhereCore")]),
        .target(
            name: "WhereTesting",
            destinations: iosDestinations,
            product: .framework,
            bundleId: "com.stuff.wheretesting",
            deploymentTargets: iosDeployment,
            sources: ["Where/WhereTesting/Sources/**"],
            dependencies: [],
        ),
        .target(
            name: "Where",
            destinations: iosDestinations,
            product: .app,
            bundleId: "com.stuff.where",
            deploymentTargets: iosDeployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "UIApplicationSupportsIndirectInputEvents": .boolean(true),
            ]),
            sources: ["Where/Where/Sources/**"],
            resources: ["Where/Where/Resources/**"],
            dependencies: [.target(name: "WhereUI")],
        ),
        hostedIOSUnitTests(moduleName: "StuffCore", bundleIdSuffix: "stuffcore", sourcesRoot: "Shared"),
        hostedIOSUnitTests(moduleName: "WhereCore", bundleIdSuffix: "wherecore", sourcesRoot: "Where"),
        hostedIOSUnitTests(moduleName: "WhereUI", bundleIdSuffix: "whereui", sourcesRoot: "Where"),
        .target(
            name: "WhereTests",
            destinations: iosDestinations,
            product: .unitTests,
            bundleId: "com.stuff.where.tests",
            deploymentTargets: iosDeployment,
            sources: ["Where/Where/Tests/**"],
            dependencies: [
                .target(name: "Where"),
                .target(name: "WhereTesting"),
            ],
        ),
    ],
)
