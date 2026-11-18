@_spi(Capture) import SnapshotKit
import SnapshotTesting
import Testing
import UIKit

/// One immutable comparison worker overlaps the next serial hosted capture.
/// The structured scope drains before a cutsheet, cancellation, or provider exit.
@MainActor
func assertOverlappingSnapshots(
    _ snapshots: [SnapshotCase],
    record: SnapshotTestingConfiguration.Record?,
    fileID: StaticString,
    file filePath: StaticString,
    testName: String,
    line: UInt,
    column: UInt,
    prepare: @escaping @Sendable (Data, URL, Bool) async
        -> SnapshotPreparedComparison = { png, reference, diagnostics in
            await prepareSnapshotReference(
                capturedPNG: png,
                referenceURL: reference,
                diagnostics: diagnostics,
            )
        },
) async {
    let source = SnapshotAssertionSource(
        fileID: fileID,
        filePath: filePath,
        testName: testName,
        line: line,
        column: column,
    )
    await withTaskGroup(of: SnapshotPreparedComparison.self) { workers in
        var pending: PendingSnapshotAssertion?
        for snapshotCase in snapshots {
            guard !Task.isCancelled else { return }
            switch snapshotCase.capture {
                case .cutsheet:
                    await finishPendingAssertion(&pending, workers: &workers)
                    guard !Task.isCancelled else { return }
                    await assertComparisonSnapshots(
                        snapshotCase,
                        record: record,
                        fileID: fileID,
                        file: filePath,
                        testName: testName,
                        line: line,
                        column: column,
                    )
                case let .single(content):
                    for configuration in snapshotCase.configurations {
                        guard !Task.isCancelled else { return }
                        let identifier = fullSnapshotIdentifier(
                            caseName: snapshotCase.name,
                            configuration: configuration,
                        )
                        let result: Result<ConfiguredSnapshotCapture, Error>
                        do {
                            let capture = try await captureConfiguredSnapshot(
                                of: content(),
                                configuration: configuration,
                                named: identifier,
                                measurementReadiness: snapshotCase.measurementReadiness,
                                onReadyToMeasure: snapshotCase.onReadyToMeasure,
                                measurementHookTimeout: nil,
                                settle: snapshotCase.settle,
                                prepareForCapture: snapshotCase.prepareForCapture,
                                onReadyToSnapshot: snapshotCase.onReadyToSnapshot,
                                timeoutPolicy: .fromEnvironment(),
                            )
                            capture.timing.finishCapture()
                            result = .success(capture)
                        } catch {
                            result = .failure(error)
                        }
                        // Preserve comparison/error order even if this capture failed.
                        await finishPendingAssertion(&pending, workers: &workers)
                        guard !Task.isCancelled else { return }
                        switch result {
                            case .failure(is CancellationError):
                                return
                            case let .failure(error):
                                Issue.record(error)
                            case let .success(capture):
                                let current = PendingSnapshotAssertion(
                                    pngData: capture.capture.pngData,
                                    timing: capture.timing,
                                    identifier: identifier,
                                    configuration: configuration,
                                    referenceGroup: snapshotCase.referenceGroup,
                                    record: record,
                                    source: source,
                                )
                                guard record != .all,
                                      let pixels = capture.capture.image.cgImage,
                                      pixels.width * pixels.height
                                      <= SnapshotPreparedComparison.maximumPixelCount
                                else {
                                    await current.finish(preparation: nil)
                                    continue
                                }
                                // Copy only Sendable inputs; never transfer hosted state.
                                let png = current.pngData
                                let reference = current.referenceURL
                                let diagnostics = SnapshotDiffReporting.isEnabledByEnvironment
                                pending = current
                                workers.addTask { await prepare(png, reference, diagnostics) }
                        }
                    }
            }
        }
        await finishPendingAssertion(&pending, workers: &workers)
    }
}

@MainActor
private func finishPendingAssertion(
    _ pending: inout PendingSnapshotAssertion?,
    workers: inout TaskGroup<SnapshotPreparedComparison>,
) async {
    guard let previous = pending else { return }
    pending = nil
    guard let preparation = await workers.next() else {
        preconditionFailure("A pending assertion must own one comparison worker")
    }
    guard !Task.isCancelled else { return }
    await previous.finish(preparation: preparation)
}

private struct SnapshotAssertionSource {
    let fileID: StaticString
    let filePath: StaticString
    let testName: String
    let line: UInt
    let column: UInt
}

@MainActor
private struct PendingSnapshotAssertion {
    let pngData: Data
    let timing: SnapshotCaptureTiming
    let identifier: String
    let configuration: SnapshotConfiguration
    let referenceGroup: SnapshotReferenceGroup?
    let record: SnapshotTestingConfiguration.Record?
    let source: SnapshotAssertionSource

    var referenceURL: URL {
        snapshotReferenceURL(
            testFilePath: source.filePath.description,
            testName: source.testName,
            identifier: identifier,
            configuration: configuration,
            referenceGroup: referenceGroup,
        )
    }

    func finish(preparation: SnapshotPreparedComparison?) async {
        let prepared: SnapshotPreparedMatch?
        switch preparation?.outcome {
            case let .matched(match): prepared = match
            case .serial, .none: prepared = nil
            case .cancelled: return
        }
        if let preparation {
            timing.recordPreparedComparison(duration: preparation.duration)
        }
        await timing.measure(.compare) {
            await assertSnapshotReference(
                .imagePNG(pngData),
                identifier: identifier,
                configuration: configuration,
                referenceGroup: referenceGroup,
                record: record,
                diffTool: environmentDiffTool(),
                fileID: source.fileID,
                file: source.filePath,
                testName: source.testName,
                line: source.line,
                column: source.column,
                prepared: prepared,
            )
        }
        timing.emit()
    }
}
