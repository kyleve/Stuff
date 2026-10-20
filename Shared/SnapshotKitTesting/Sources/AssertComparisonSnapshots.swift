import SnapshotKit
import SnapshotTesting
import TestHostSupport
import Testing
import UIKit

/// Keeps comparison subjects on the same hosted capture path as ordinary cases.
@MainActor
func assertComparisonSnapshots(
    _ snapshotCase: SnapshotCase,
    record: SnapshotTestingConfiguration.Record?,
    fileID: StaticString,
    file filePath: StaticString,
    testName: String,
    line: UInt,
    column: UInt,
) async {
    for configuration in snapshotCase.configurations {
        do {
            try Task.checkCancellation()
            let identifier = fullSnapshotIdentifier(
                caseName: snapshotCase.name,
                configuration: configuration,
            )
            let sheet = try await captureComparisonSheet(snapshotCase, configuration: configuration)
            let reference = snapshotReferenceURL(
                testFilePath: "\(filePath)",
                testName: testName,
                identifier: identifier,
                configuration: configuration,
                referenceGroup: snapshotCase.referenceGroup,
            )
            if SnapshotDiffReporting.isEnabledByEnvironment, let png = sheet.image.pngData() {
                SnapshotDiffReporting.report(
                    compareAgainstReference(capturedPNG: png, referenceURL: reference),
                    identifier: identifier,
                    reference: reference,
                )
            }
            withSnapshotTesting(
                record: record ?? environmentRecordMode(),
                diffTool: environmentDiffTool(),
            ) {
                let layoutFailure = verifySnapshot(
                    of: sheet.layout,
                    as: .json,
                    named: identifier,
                    snapshotDirectory: reference.deletingLastPathComponent().path,
                    fileID: fileID,
                    file: filePath,
                    testName: testName,
                    line: line,
                    column: column,
                )
                let imageFailure = verifySnapshot(
                    of: sheet.image,
                    as: SnapshotComparisonSheet.strategy(layout: sheet.layout),
                    named: identifier,
                    snapshotDirectory: reference.deletingLastPathComponent().path,
                    fileID: fileID,
                    file: filePath,
                    testName: testName,
                    line: line,
                    column: column,
                )
                for failure in [layoutFailure, imageFailure].compactMap(\.self) {
                    Issue.record(Comment(rawValue: failure), sourceLocation: SourceLocation(
                        fileID: fileID.description,
                        filePath: filePath.description,
                        line: Int(line),
                        column: Int(column),
                    ))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            Issue.record(error)
        }
    }
}

/// Captures a single configuration without recording; the assertion runner and
/// hosted regression tests exercise this same path.
@MainActor
func captureComparisonSheet(
    _ snapshotCase: SnapshotCase,
    configuration: SnapshotConfiguration,
) async throws -> SnapshotComparisonSheet {
    try waitFor { hostKeyWindow()?.rootViewController != nil }
    let identifier = fullSnapshotIdentifier(
        caseName: snapshotCase.name,
        configuration: configuration,
    )
    var panels: [SnapshotComparisonSheet.Panel] = []
    for panel in snapshotCase.comparisonPanels {
        let sizing: SnapshotSizing = switch configuration.device.size {
            case .fixed: .fixed
            case let .intrinsic(width): .intrinsic(
                    width: width ?? UIScreen.main.bounds.width,
                    minimumHeight: 0,
                )
            case let .fullContent(width, minimumHeight): .intrinsic(
                    width: width,
                    minimumHeight: minimumHeight ?? 0,
                )
            case let .fullContent2D(minimumSize): .fullContent2D(minimumSize: minimumSize)
        }
        let panelName = "\(identifier)/\(panel.id.rawValue)"
        let timing = SnapshotCaptureTiming(
            identifier: panelName,
            isEnabled: SnapshotCaptureTiming.isEnabledByEnvironment,
            sizing: sizing,
            measurementReadiness: snapshotCase.measurementReadiness,
            captureSettle: snapshotCase.settle,
        )
        let capture = try await renderSnapshotCapture(
            of: makeHostingController(for: panel.content, configuration: configuration),
            named: panelName,
            sizing: sizing,
            safeAreaInsets: configuration.device.safeAreaInsets.uiEdgeInsets,
            isAccessibility: configuration.snapshotType == .accessibility,
            measurementReadiness: snapshotCase.measurementReadiness,
            onReadyToMeasure: snapshotCase.onReadyToMeasure,
            settle: snapshotCase.settle,
            onReadyToSnapshot: snapshotCase.onReadyToSnapshot,
            settleTimeoutPolicy: .fromEnvironment(),
            timing: timing,
        )
        timing.emit()
        let image = capture.image
        panels.append(.init(identity: panel.id, label: panel.label, image: image))
    }
    return try SnapshotComparisonSheet(panels: panels)
}
