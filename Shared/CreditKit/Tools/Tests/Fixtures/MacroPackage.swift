import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Fixture",
    dependencies: [
        .package(url: "https://example.com/fake-runtime", exact: "1.0.0"),
        .package(url: "https://example.com/fake-syntax", exact: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Shipping",
            dependencies: [
                .target(name: "FixtureMacro"),
                .product(name: "FakeRuntime", package: "fake-runtime"),
            ],
        ),
        .macro(
            name: "FixtureMacro",
            dependencies: [
                .product(name: "FakeSyntax", package: "fake-syntax"),
            ],
        ),
    ],
)
