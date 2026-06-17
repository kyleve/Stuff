import ProjectDescription

/// Standalone Mac Catalyst viewer for the graph.json that code-graph-extract
/// emits. It depends only on the dependency-free CodeGraphModel package next
/// door, and reads a user-selected graph.json through a security-scoped
/// bookmark so the app stays sandboxed.
let project = Project(
    name: "CodeGraphViewer",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en",
    ),
    packages: [
        .local(path: .relativeToManifest("../CodeGraphModel")),
    ],
    settings: .settings(base: [
        "SUPPORTS_MACCATALYST": "YES",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "TARGETED_DEVICE_FAMILY": "2",
        "MARKETING_VERSION": "1.0",
        "CURRENT_PROJECT_VERSION": "1",
    ]),
    targets: [
        .target(
            name: "CodeGraphViewer",
            destinations: [.macCatalyst],
            product: .app,
            bundleId: "com.stuff.codegraph.viewer",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "CFBundleDisplayName": .string("CodeGraph"),
                "UIApplicationSupportsIndirectInputEvents": .boolean(true),
            ]),
            sources: ["CodeGraphViewer/Sources/**"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": .boolean(true),
                "com.apple.security.files.user-selected.read-only": .boolean(true),
                "com.apple.security.files.bookmarks.app-scope": .boolean(true),
            ]),
            dependencies: [
                .package(product: "CodeGraphModel"),
            ],
        ),
    ],
)
