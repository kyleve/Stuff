import Flyover
import Foundation
import SnapshotKitTesting
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct WhereFlyoverWebExportTests {
    @Test func exportsRequestedAtlas() async throws {
        guard let environment = try WhereFlyoverExportEnvironment.current() else {
            return
        }

        let world = try await WhereFlyoverWorld.build()
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
        ) { request in
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
        print(
            "FLYOVER_EXPORT_COMPLETE \(summary.screenCount) screens "
                + "\(summary.stateCount) states \(summary.imageCount) images "
                + "\(summary.outputByteCount) bytes",
        )
    }
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
