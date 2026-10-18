import SnapshotKit
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Renders static, self-contained HTML in WebKit, then compares its pixels through the
/// standard hosted pipeline. Each configuration gets a fresh, offline web view.
/// Only standard, full-content configurations are supported; these are not
/// accessibility-tree snapshots or a simulation of Safari's browser chrome.
@MainActor
public func assertHTMLSnapshots(
    of html: String,
    named name: String,
    configurations: [SnapshotConfiguration],
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) async throws {
    let duplicates = duplicateSnapshotIdentifiers(in: [
        SnapshotCase(name: name, configurations: configurations) { EmptyView() },
    ])
    guard duplicates.isEmpty else {
        Issue.record("Duplicate HTML snapshot identifiers: \(duplicates.joined(separator: ", "))")
        return
    }
    for configuration in configurations {
        let image = try await loadHTMLSnapshotImage(html, configuration: configuration)
        await assertSnapshots(
            of: Image(uiImage: image),
            named: name,
            configurations: [configuration],
            measurementReadiness: .immediate,
            record: record,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column,
        )
    }
}

/// WebKit supplies remote-process pixels before SnapshotKit's normal PNG,
/// comparison, timing, and diff pipeline. This seam also permits pixel probes.
@MainActor
@_spi(Testing) public func loadHTMLSnapshotImage(
    _ html: String,
    configuration: SnapshotConfiguration,
) async throws -> UIImage {
    try await SnapshotCaptureLock.withLock {
        try Task.checkCancellation()
        guard configuration.snapshotType == .standard,
              case let .fullContent(width, minimumHeight) = configuration.device.size
        else { throw SnapshotWebPage.Failure.requiresStandardFullContent }
        return try await SnapshotWebPage.capture(
            html,
            width: width,
            minimumHeight: minimumHeight ?? 1,
            traits: configuration.uiTraitCollection,
        )
    }
}
