import ProjectDescription

let mobileDestinations: Destinations = [.iPhone, .iPad, .macCatalyst]
let mobileDeployment: DeploymentTargets = .iOS("26.0")

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
            destinations: mobileDestinations,
            product: .framework,
            bundleId: "com.stuff.\(bundleIdSuffix)",
            deploymentTargets: mobileDeployment,
            sources: ["\(name)/Sources/**"],
            dependencies: dependencies
        ),
        .target(
            name: "\(name)Tests",
            destinations: mobileDestinations,
            product: .unitTests,
            bundleId: "com.stuff.\(bundleIdSuffix).tests",
            deploymentTargets: mobileDeployment,
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

func mobileApp(
    _ name: String,
    bundleIdSuffix: String,
    infoPlist: [String: Plist.Value] = [:],
    dependencies: [TargetDependency] = []
) -> [Target] {
    [
        .target(
            name: name,
            destinations: mobileDestinations,
            product: .app,
            bundleId: "com.stuff.\(bundleIdSuffix)",
            deploymentTargets: mobileDeployment,
            infoPlist: .extendingDefault(with: infoPlist),
            sources: ["\(name)/Sources/**"],
            resources: ["\(name)/Resources/**"],
            dependencies: dependencies
        ),
        .target(
            name: "\(name)Tests",
            destinations: mobileDestinations,
            product: .unitTests,
            bundleId: "com.stuff.\(bundleIdSuffix).tests",
            deploymentTargets: mobileDeployment,
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
    targets: mobileApp(
        "PhotoFramer",
        bundleIdSuffix: "photo-framer",
        infoPlist: [
            "NSPhotoLibraryUsageDescription": .string("Photo Framer needs access to your photo library to import photos."),
            "NSPhotoLibraryAddUsageDescription": .string("Photo Framer needs permission to save framed photos to your library."),
            "UILaunchScreen": .dictionary([:]),
        ]
    )
)
