import ProjectDescription

let macDestinations: Destinations = [.mac]
let macDeployment: DeploymentTargets = .macOS("26.0")

func framework(
    _ name: String,
    bundleIdSuffix: String,
    dependencies: [TargetDependency] = []
) -> [Target] {
    [
        .target(
            name: name,
            destinations: macDestinations,
            product: .framework,
            bundleId: "com.stuff.\(bundleIdSuffix)",
            deploymentTargets: macDeployment,
            sources: ["\(name)/Sources/**"],
            dependencies: dependencies
        ),
        .target(
            name: "\(name)Tests",
            destinations: macDestinations,
            product: .unitTests,
            bundleId: "com.stuff.\(bundleIdSuffix).tests",
            deploymentTargets: macDeployment,
            sources: ["\(name)/Tests/**"],
            dependencies: [.target(name: name)]
        ),
    ]
}

func macApp(
    _ name: String,
    bundleIdSuffix: String,
    infoPlist: [String: Plist.Value] = [:],
    dependencies: [TargetDependency] = []
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
            dependencies: dependencies
        ),
        .target(
            name: "\(name)Tests",
            destinations: macDestinations,
            product: .unitTests,
            bundleId: "com.stuff.\(bundleIdSuffix).tests",
            deploymentTargets: macDeployment,
            sources: ["\(name)/Tests/**"],
            dependencies: [.target(name: name)]
        ),
    ]
}

let project = Project(
    name: "Stuff",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    targets: []
)
