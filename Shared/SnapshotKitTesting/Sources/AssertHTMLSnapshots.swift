import SnapshotKit
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Renders static, self-contained HTML through the standard hosted view pipeline. Each
/// configuration gets a fresh, offline web view.
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
        let page = try await SnapshotWebPage.make(html, configuration: configuration)
        defer { page.stop() }
        await assertSnapshots(
            of: SnapshotWebPageView(page: page),
            named: name,
            configurations: [configuration],
            measurementReadiness: .immediate,
            onReadyToMeasure: { try await page.prepare() },
            measurementHookTimeout: SnapshotWebPage.readinessTimeout,
            record: record,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column,
        )
    }
}

/// Pixel-probe seam using the same view, readiness hook, and renderer as assertions.
@MainActor
@_spi(Testing) public func loadHTMLSnapshotImage(
    _ html: String,
    configuration: SnapshotConfiguration,
) async throws -> UIImage {
    let page = try await SnapshotWebPage.make(html, configuration: configuration)
    defer { page.stop() }
    let png = try await captureSnapshotPNG(
        of: SnapshotWebPageView(page: page),
        configuration: configuration,
        named: "html-probe",
        sizing: .intrinsic(width: page.size.width, minimumHeight: page.size.height),
        safeAreaInsets: configuration.device.safeAreaInsets.uiEdgeInsets,
        measurementReadiness: .immediate,
        onReadyToMeasure: { try await page.prepare() },
        measurementHookTimeout: SnapshotWebPage.readinessTimeout,
        settle: .settled,
        onReadyToSnapshot: nil,
    )
    guard let image = UIImage(data: png.data, scale: png.scale) else {
        throw SnapshotRenderingError.missingCGImage(name: "html-probe")
    }
    return image
}
