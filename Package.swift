// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stuff",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "StuffCore", targets: ["StuffCore"]),
        .library(name: "WhereCore", targets: ["WhereCore"]),
        .library(name: "WhereUI", targets: ["WhereUI"]),
        .library(name: "WhereTesting", targets: ["WhereTesting"]),
    ],
    targets: [
        .target(
            name: "StuffCore",
            path: "Shared/StuffCore/Sources",
        ),
        .target(
            name: "WhereCore",
            path: "Where/WhereCore/Sources",
        ),
        .target(
            name: "WhereUI",
            dependencies: [
                .target(name: "WhereCore"),
            ],
            path: "Where/WhereUI/Sources",
        ),
        .target(
            name: "WhereTesting",
            path: "Where/WhereTesting/Sources",
        ),
    ],
)
