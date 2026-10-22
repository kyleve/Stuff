import Foundation
import SnapshotKit
import SnapshotTesting
import Testing
import UIKit

/// Captured subjects remain separate until their panel verdicts are collected.
@MainActor
enum SnapshotReferenceSubject {
    case image(UIImage)
    case panels([SnapshotPanelCapture])
}

/// Shares reference paths, record-mode semantics, diagnostics, and failure reporting.
@MainActor
func assertSnapshotReference(
    _ subject: SnapshotReferenceSubject,
    identifier: String,
    configuration: SnapshotConfiguration,
    referenceGroup: SnapshotReferenceGroup?,
    record: SnapshotTestingConfiguration.Record?,
    diffTool: SnapshotTestingConfiguration.DiffTool?,
    fileID: StaticString,
    file filePath: StaticString,
    testName: String,
    line: UInt,
    column: UInt,
) async {
    let reference = snapshotReferenceURL(
        testFilePath: "\(filePath)",
        testName: testName,
        identifier: identifier,
        configuration: configuration,
        referenceGroup: referenceGroup,
    )
    let capture: SnapshotImageReference
    let png: Data
    let panelFailure: SnapshotImageReference.ComparisonFailure?
    do {
        switch subject {
            case let .image(image):
                panelFailure = nil
                capture = SnapshotImageReference(image: image, layout: nil)
            case let .panels(panels):
                if FileManager.default.fileExists(atPath: reference.path) {
                    panelFailure = try autoreleasepool {
                        try SnapshotImageReference.comparePanels(
                            referencePNG: Data(contentsOf: reference),
                            panels: panels,
                        )
                    }
                } else {
                    panelFailure = nil // The shared recorder handles missing references.
                }
                capture = try await SnapshotImageGrid.capture(panels: panels, named: identifier)
        }
        png = try autoreleasepool { try capture.pngData() }
    } catch is CancellationError {
        return
    } catch {
        Issue.record(error)
        return
    }
    // Drain synchronous comparison buffers before the next capture can begin.
    autoreleasepool {
        if SnapshotDiffReporting.isEnabledByEnvironment {
            SnapshotDiffReporting.report(
                compareAgainstReference(capturedPNG: png, referenceURL: reference),
                identifier: identifier,
                reference: reference,
            )
        }
        withSnapshotTesting(record: record, diffTool: diffTool) {
            if let failure = verifySnapshot(
                of: png,
                as: SnapshotImageReference.strategy(panelFailure: panelFailure),
                named: identifier,
                snapshotDirectory: reference.deletingLastPathComponent().path,
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column,
            ) {
                Issue.record(Comment(rawValue: failure), sourceLocation: SourceLocation(
                    fileID: fileID.description,
                    filePath: filePath.description,
                    line: Int(line),
                    column: Int(column),
                ))
            }
        }
    }
}
