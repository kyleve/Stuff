// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JournalBenchmark",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "JournalBenchmark",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v5)],
        ),
    ],
)
