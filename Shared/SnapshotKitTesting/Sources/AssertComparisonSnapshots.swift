@_spi(Capture) import SnapshotKit
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
            let panels = try await captureSnapshotPanels(snapshotCase, configuration: configuration)
            await assertSnapshotReference(
                .panels(panels),
                identifier: identifier,
                configuration: configuration,
                referenceGroup: snapshotCase.referenceGroup,
                record: record ?? environmentRecordMode(),
                diffTool: environmentDiffTool(),
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column,
            )
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
func captureSnapshotPanels(
    _ snapshotCase: SnapshotCase,
    configuration: SnapshotConfiguration,
) async throws -> [SnapshotPanelCapture] {
    try waitFor { hostKeyWindow()?.rootViewController != nil }
    let identifier = fullSnapshotIdentifier(
        caseName: snapshotCase.name,
        configuration: configuration,
    )
    guard case let .cutsheet(subjects) = snapshotCase.capture else {
        preconditionFailure("The comparison runner requires a cutsheet case")
    }
    var panels: [SnapshotPanelCapture] = []
    for panel in subjects.panels {
        let capture = try await captureConfiguredSnapshot(
            of: panel.content,
            configuration: configuration,
            named: "\(identifier)/\(panel.id.rawValue)",
            measurementReadiness: snapshotCase.measurementReadiness,
            onReadyToMeasure: snapshotCase.onReadyToMeasure,
            measurementHookTimeout: nil,
            settle: snapshotCase.settle,
            onReadyToSnapshot: snapshotCase.onReadyToSnapshot,
            timeoutPolicy: .fromEnvironment(),
        )
        capture.timing.emit()
        let image = capture.capture.image
        panels.append(.init(identity: panel.id, label: panel.label, image: image))
    }
    return panels
}
