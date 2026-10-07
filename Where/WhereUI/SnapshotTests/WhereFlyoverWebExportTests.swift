import Flyover
import Foundation
import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct WhereFlyoverWebExportTests {
    @Test func exportsRequestedAtlas() async throws {
        guard let environment = try WhereFlyoverExportEnvironment.current() else {
            return
        }

        let world = try await WhereFlyoverWorld.buildForWebExport()
        let catalog = WhereFlyoverCatalog.make(world: world)
        let exporter = FlyoverWebExporter(
            catalog: catalog,
            applicationID: "where",
            title: "Where",
            screenIdentifier: \WhereFlyoverScreenID.exportIdentifier,
        )
        let summary = try await exporter.export(
            to: environment.outputDirectory,
            profiles: environment.profiles,
            build: environment.build,
            capture: capture,
        )
        print(
            "FLYOVER_EXPORT_COMPLETE \(summary.screenCount) screens "
                + "\(summary.stateCount) states \(summary.imageCount) images "
                + "\(summary.outputByteCount) bytes",
        )
    }

    @Test func exportsHostedSmokeAtlas() async throws {
        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhereFlyoverHostedSmoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: output)
            } catch {
                Issue.record(error)
            }
        }
        try copyWebShell(to: output)

        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("primary"),
                    title: "Primary",
                    root: SmokeScreen.root,
                    screens: [
                        FlyoverScreen(
                            id: SmokeScreen.root,
                            title: "Root",
                            variants: [
                                FlyoverVariant(
                                    id: FlyoverVariantID("viewport"),
                                    title: "Viewport",
                                ) {
                                    Text("Root")
                                },
                            ],
                        ),
                    ],
                ),
                FlyoverGroup(
                    id: FlyoverGroupID("details"),
                    title: "Details",
                    root: SmokeScreen.details,
                    screens: [
                        FlyoverScreen(
                            id: SmokeScreen.details,
                            title: "Details",
                            variants: [
                                FlyoverVariant(
                                    id: FlyoverVariantID("full-content"),
                                    title: "Full Content",
                                    exportPolicy: FlyoverExportPolicy(
                                        captureExtent: .fullContent,
                                        measurementReadiness: .immediate,
                                        settle: .immediate,
                                        onReadyToMeasure: nil,
                                        onReadyToSnapshot: nil,
                                    ),
                                ) {
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            Color.red.frame(height: 500)
                                            Color.blue.frame(height: 500)
                                        }
                                    }
                                },
                            ],
                        ),
                    ],
                ),
            ],
            transitions: [
                FlyoverTransition(from: .root, to: .details, kind: .push),
                FlyoverTransition(from: .details, to: .root, kind: .modal),
            ],
        )
        let exporter = FlyoverWebExporter(
            catalog: catalog,
            applicationID: "smoke",
            title: "Hosted Smoke",
            screenIdentifier: \SmokeScreen.rawValue,
        )
        let summary = try await exporter.export(
            to: output,
            profiles: [.phoneLight, .phoneDark],
            build: FlyoverExportBuild(
                commit: "smoke",
                dirty: false,
                branch: nil,
                generatedAt: "2026-09-03T00:00:00Z",
                xcodeVersion: "Tests",
                simulatorDevice: "StuffTestHost",
                simulatorOS: "Tests",
            ),
            capture: capture,
        )

        let data = try Data(contentsOf: output.appending(path: "manifest.json"))
        let manifest = try JSONDecoder().decode(FlyoverWebManifest.self, from: data)
        #expect(manifest.schemaVersion == 1)
        #expect(summary.screenCount == 2)
        #expect(summary.stateCount == 2)
        #expect(summary.profileCount == 2)
        #expect(summary.imageCount == 4)
        #expect(summary.outputByteCount > 0)
        #expect(summary.outputDirectory == output)
        #expect(manifest.profiles.map(\.id) == ["phone-light", "phone-dark"])
        #expect(manifest.groups.map { group in
            [group.id, group.rootScreenID] + group.screenIDs
        } == [
            ["primary", "root", "root"],
            ["details", "details", "details"],
        ])

        let root = try #require(manifest.screens.first { $0.id == "root" })
        let details = try #require(manifest.screens.first { $0.id == "details" })
        let rootVariant = try #require(root.variants.first)
        let detailsVariant = try #require(details.variants.first)
        #expect(rootVariant.id == "viewport")
        #expect(rootVariant.captureExtent == "viewport")
        #expect(rootVariant.imagesByProfile == [
            "phone-light": "images/screen-0001/variant-0001/phone-light.png",
            "phone-dark": "images/screen-0001/variant-0001/phone-dark.png",
        ])
        #expect(detailsVariant.id == "full-content")
        #expect(detailsVariant.captureExtent == "fullContent")
        #expect(detailsVariant.imagesByProfile == [
            "phone-light": "images/screen-0002/variant-0001/phone-light.png",
            "phone-dark": "images/screen-0002/variant-0001/phone-dark.png",
        ])

        #expect(manifest.routes.map { route in
            [
                route.id,
                route.sourceScreenID,
                route.destinationScreenID,
                route.kind,
                route.label ?? "",
            ]
        } == [
            ["route-0001", "root", "details", "push", ""],
            ["route-0002", "details", "root", "modal", ""],
        ])
        #expect(root.incomingRouteIDs == ["route-0002"])
        #expect(root.outgoingRouteIDs == ["route-0001"])
        #expect(details.incomingRouteIDs == ["route-0001"])
        #expect(details.outgoingRouteIDs == ["route-0002"])
        #expect(manifest.canvas.connectors.map(\.routeID) == ["route-0001", "route-0002"])

        #expect(manifest.images.count == 4)
        #expect(manifest.images.map { image in
            [
                image.screenID,
                image.variantID,
                image.profileID,
                image.relativePath,
                image.captureExtent,
            ]
        } == [
            [
                "root",
                "viewport",
                "phone-light",
                "images/screen-0001/variant-0001/phone-light.png",
                "viewport",
            ],
            [
                "root",
                "viewport",
                "phone-dark",
                "images/screen-0001/variant-0001/phone-dark.png",
                "viewport",
            ],
            [
                "details",
                "full-content",
                "phone-light",
                "images/screen-0002/variant-0001/phone-light.png",
                "fullContent",
            ],
            [
                "details",
                "full-content",
                "phone-dark",
                "images/screen-0002/variant-0001/phone-dark.png",
                "fullContent",
            ],
        ])
        for image in manifest.images {
            #expect(image.relativePath.hasPrefix("/") == false)
            #expect(image.pointWidth == 402)
            if image.screenID == "root" {
                #expect(image.pointHeight == 874)
            } else {
                #expect(image.pointHeight > 874)
            }
            #expect(image.pixelWidth == Int((image.pointWidth * image.scale).rounded()))
            #expect(image.pixelHeight == Int((image.pointHeight * image.scale).rounded()))

            let imageURL = output.appending(path: image.relativePath)
            let pngData = try Data(contentsOf: imageURL)
            let decodedImage = try #require(UIImage(data: pngData, scale: CGFloat(image.scale)))
            let pixels = try #require(decodedImage.cgImage)
            #expect(pixels.width == image.pixelWidth)
            #expect(pixels.height == image.pixelHeight)
        }
        for path in [
            "index.html",
            "manifest.json",
            "manifest.js",
            "assets/app.js",
            "assets/styles.css",
        ] {
            #expect(FileManager.default.fileExists(
                atPath: output.appending(path: path).path,
            ))
        }
        let shell = try ["index.html", "assets/app.js", "assets/styles.css"]
            .map { path in try String(contentsOf: output.appending(path: path), encoding: .utf8) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "http://www.w3.org/2000/svg", with: "")
        #expect(shell.contains("http://") == false)
        #expect(shell.contains("https://") == false)
        #expect(shell.contains("fetch(") == false)
    }

    private func capture(_ request: FlyoverCaptureRequest) async throws -> FlyoverCapturedImage {
        let capture = try await captureSnapshotPNG(
            of: request.content,
            configuration: request.configuration,
            named: request.captureName,
            sizing: request.configuration.snapshotSizing,
            safeAreaInsets: request.configuration.device.safeAreaInsets.uiEdgeInsets,
            measurementReadiness: request.measurementReadiness,
            onReadyToMeasure: request.onReadyToMeasure,
            settle: request.settle,
            onReadyToSnapshot: request.onReadyToSnapshot,
        )
        return FlyoverCapturedImage(
            pngData: capture.data,
            pointSize: capture.pointSize,
            pixelSize: capture.pixelSize,
            scale: capture.scale,
        )
    }

    private func copyWebShell(to output: URL) throws {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = repository.appending(path: "Shared/Flyover/Web")
        let assets = output.appending(path: "assets", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: source.appending(path: "index.html"),
            to: output.appending(path: "index.html"),
        )
        for filename in ["app.js", "styles.css"] {
            try FileManager.default.copyItem(
                at: source.appending(path: "assets/\(filename)"),
                to: assets.appending(path: filename),
            )
        }
    }
}

private enum SmokeScreen: String {
    case root
    case details
}

private struct WhereFlyoverExportEnvironment {
    let outputDirectory: URL
    let profiles: [FlyoverCaptureProfile]
    let build: FlyoverExportBuild

    static func current() throws -> Self? {
        let values = ProcessInfo.processInfo.environment
        guard let output = values["FLYOVER_EXPORT_DIRECTORY"], output.isEmpty == false else {
            return nil
        }
        let identifiers = values["FLYOVER_EXPORT_PROFILES"]?
            .split(separator: ",")
            .map(String.init) ?? []
        return try WhereFlyoverExportEnvironment(
            outputDirectory: URL(filePath: output, directoryHint: .isDirectory),
            profiles: FlyoverCaptureProfile.parse(identifiers),
            build: FlyoverExportBuild(
                commit: values["FLYOVER_EXPORT_COMMIT"] ?? "unknown",
                dirty: values["FLYOVER_EXPORT_DIRTY"] == "true",
                branch: values["FLYOVER_EXPORT_BRANCH"].flatMap { $0.isEmpty ? nil : $0 },
                generatedAt: values["FLYOVER_EXPORT_GENERATED_AT"] ?? "unknown",
                xcodeVersion: values["FLYOVER_EXPORT_XCODE_VERSION"] ?? "unknown",
                simulatorDevice: values["FLYOVER_EXPORT_SIMULATOR_DEVICE"] ?? "unknown",
                simulatorOS: values["FLYOVER_EXPORT_SIMULATOR_OS"] ?? "unknown",
            ),
        )
    }
}

extension SnapshotConfiguration {
    fileprivate var snapshotSizing: SnapshotSizing {
        switch device.size {
            case .fixed:
                .fixed
            case let .intrinsic(maxWidth):
                .intrinsic(width: maxWidth ?? UIScreen.main.bounds.width, minimumHeight: 0)
            case let .fullContent(width, minimumHeight):
                .intrinsic(width: width, minimumHeight: minimumHeight ?? 0)
            case let .fullContent2D(minimumSize):
                .fullContent2D(minimumSize: minimumSize)
        }
    }
}
