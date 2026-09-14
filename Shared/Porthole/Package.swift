// swift-tools-version: 6.2
import PackageDescription

/// Reuses runtime sources for host qualification without planning application-only dependencies.
let package = Package(
    name: "Porthole",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PortholeCore", targets: ["PortholeCore"]),
        .library(name: "PortholeRuntime", targets: ["PortholeRuntime"]),
        .library(name: "PortholeJavaScript", targets: ["PortholeJavaScript"]),
        .library(name: "PortholeAgent", targets: ["PortholeAgent"]),
        .library(name: "PortholeGitHub", targets: ["PortholeGitHub"]),
        .library(name: "PortholeRemote", targets: ["PortholeRemote"]),
        .executable(name: "porthole", targets: ["PortholeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/zaidmukaddam/swift-ai-sdk.git", exact: "0.3.0"),
        .package(path: "PortholeCertificates"),
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols", exact: "7.0.0"),
    ],
    targets: [
        // The host qualification target omits the application's iOS style and snapshot graph.
        .target(name: "PortholeUI", dependencies: [
            "PortholeRuntime",
            "PortholeJavaScript",
            "PortholeAgent",
            "PortholeGitHub",
            "PortholeRemote",
            .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
        ], path: "PortholeUI/Sources"),
        .target(name: "PortholeCore", path: "PortholeCore/Sources"),
        .target(
            name: "PortholeRuntime",
            dependencies: ["PortholeCore"],
            path: "PortholeRuntime/Sources",
        ),
        .target(
            name: "CQuickJS",
            path: "CQuickJS/Sources",
            publicHeadersPath: "include",
            cSettings: [.define("QUICKJS_NG_BUILD"), .define("_GNU_SOURCE")],
        ),
        .target(
            name: "PortholeJavaScript",
            dependencies: ["CQuickJS", "PortholeCore"],
            path: "PortholeJavaScript/Sources",
        ),
        .target(
            name: "PortholeAgent",
            dependencies: ["PortholeCore", .product(name: "AI", package: "swift-ai-sdk")],
            path: "PortholeAgent/Sources",
        ),
        .target(name: "PortholeGitHub", path: "PortholeGitHub/Sources"),
        .target(
            name: "PortholeRemote",
            dependencies: [
                "PortholeCore",
                .product(name: "PortholeCertificates", package: "PortholeCertificates"),
            ],
            path: "PortholeRemote/Sources",
        ),
        .executableTarget(
            name: "PortholeCLI",
            dependencies: ["PortholeCore", "PortholeRemote"],
            path: "PortholeCLI/Sources",
        ),
        .testTarget(
            name: "PortholeCoreTests",
            dependencies: ["PortholeCore"],
            path: "PortholeCore/Tests",
        ),
        .testTarget(
            name: "PortholeRuntimeTests",
            dependencies: ["PortholeCore", "PortholeRuntime"],
            path: "PortholeRuntime/Tests",
        ),
        .testTarget(
            name: "PortholeJavaScriptTests",
            dependencies: ["PortholeCore", "PortholeJavaScript"],
            path: "PortholeJavaScript/Tests",
        ),
        .testTarget(
            name: "PortholeAgentTests",
            dependencies: [
                "PortholeCore",
                "PortholeAgent",
                .product(name: "AI", package: "swift-ai-sdk"),
            ],
            path: "PortholeAgent/Tests",
        ),
        .testTarget(
            name: "PortholeGitHubTests",
            dependencies: ["PortholeGitHub"],
            path: "PortholeGitHub/Tests",
        ),
        .testTarget(
            name: "PortholeRemoteTests",
            dependencies: ["PortholeCore", "PortholeRemote"],
            path: "PortholeRemote/Tests",
        ),
        .testTarget(
            name: "PortholeUITests",
            dependencies: [
                "PortholeUI",
                "PortholeAgent",
                "PortholeRuntime",
                "PortholeRemote",
                "PortholeGitHub",
            ],
            path: "PortholeUI/Tests",
        ),
    ],
)
