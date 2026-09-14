// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortholeCertificates",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PortholeCertificates", type: .dynamic, targets: ["PortholeCertificates"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.20.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.2"),
    ],
    targets: [
        .target(
            name: "PortholeCertificates",
            dependencies: [
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            path: "Sources",
        ),
        .testTarget(
            name: "PortholeCertificatesTests",
            dependencies: ["PortholeCertificates"],
            path: "Tests",
        ),
    ],
)
