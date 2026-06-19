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
        // The iOS 26 deployment target otherwise derives a Mac Catalyst macOS
        // deployment of 27.0, which won't launch (or run unit tests) on a
        // macOS 26 host. Pin it down to the matching macOS so the Catalyst app
        // and its test bundle run locally.
        "MACOSX_DEPLOYMENT_TARGET": "26.0",
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
                // Declare we can view JSON so `open -a CodeGraph graph.json`
                // (used by run.sh) hands the file to us via onOpenURL with a
                // sandbox grant. Rank Alternate so we don't steal the user's
                // default .json association.
                "CFBundleDocumentTypes": .array([
                    .dictionary([
                        "CFBundleTypeName": .string("Code graph"),
                        "CFBundleTypeRole": .string("Viewer"),
                        "LSHandlerRank": .string("Alternate"),
                        "LSItemContentTypes": .array([.string("public.json")]),
                    ]),
                ]),
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
        .target(
            name: "CodeGraphViewerTests",
            destinations: [.macCatalyst],
            product: .unitTests,
            bundleId: "com.stuff.codegraph.viewer.tests",
            deploymentTargets: .iOS("26.0"),
            sources: ["CodeGraphViewerTests/Sources/**"],
            dependencies: [
                .target(name: "CodeGraphViewer"),
                .package(product: "CodeGraphModel"),
            ],
        ),
    ],
    schemes: [
        .scheme(
            name: "CodeGraphViewer",
            shared: true,
            buildAction: .buildAction(targets: ["CodeGraphViewer", "CodeGraphViewerTests"]),
            testAction: .targets(["CodeGraphViewerTests"]),
            runAction: .runAction(executable: "CodeGraphViewer"),
        ),
    ],
)
