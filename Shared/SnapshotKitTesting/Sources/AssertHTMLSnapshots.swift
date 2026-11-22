import SnapshotKit
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// A static, self-contained document and the configurations to capture it in.
public struct HTMLSnapshotDocument: Sendable {
    public let html: String
    public let name: String
    public let configurations: [SnapshotConfiguration]

    public init(html: String, name: String, configurations: [SnapshotConfiguration]) {
        self.html = html
        self.name = name
        self.configurations = configurations
    }
}

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
    try await assertHTMLDocuments(
        [.init(html: html, name: name, configurations: configurations)],
        reusingWebView: false,
        record: record,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column,
    )
}

/// Captures an ordered batch in one offline web view. Each variant loads a new document
/// and waits for its embedded images to decode. The batch owns the view for this call.
@MainActor
public func assertHTMLSnapshots(
    of documents: [HTMLSnapshotDocument],
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) async throws {
    try await assertHTMLDocuments(
        documents,
        reusingWebView: true,
        record: record,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column,
    )
}

@MainActor
private func assertHTMLDocuments(
    _ documents: [HTMLSnapshotDocument],
    reusingWebView: Bool,
    record: SnapshotTestingConfiguration.Record?,
    fileID: StaticString,
    file filePath: StaticString,
    testName: String,
    line: UInt,
    column: UInt,
) async throws {
    let cases = documents.map { document in
        SnapshotCase(name: document.name, configurations: document.configurations) { EmptyView() }
    }
    let duplicates = duplicateSnapshotIdentifiers(in: cases)
    guard duplicates.isEmpty else {
        Issue.record("Duplicate HTML snapshot identifiers: \(duplicates.joined(separator: ", "))")
        return
    }
    var reusableView: SnapshotWebPage.DocumentView?
    for document in documents {
        for configuration in document.configurations {
            let page = try await SnapshotWebPage.make(
                document.html,
                configuration: configuration,
                reusing: reusableView,
                decodesImages: reusingWebView,
            )
            defer { page.stop() }
            await assertSnapshots(
                of: SnapshotWebPageView(page: page),
                named: document.name,
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
            reusableView = reusingWebView ? page.reusableWebView : nil
        }
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
