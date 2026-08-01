import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct YearExportModelTests {
    @Test func eachPresentationStartsWithEphemeralFieldsAndRawGPSOff() throws {
        let first = try makeModel(renderer: ScriptedYearPDFRenderer([.success]))
        first.preparedFor = "Accountant"
        first.reference = "Ref"
        first.includeRawGPS = true

        let second = try makeModel(renderer: ScriptedYearPDFRenderer([.success]))

        #expect(second.preparedFor.isEmpty)
        #expect(second.reference.isEmpty)
        #expect(!second.includeRawGPS)
    }

    @Test func progressAndSuccessProduceAReadyFile() async throws {
        let renderer = ScriptedYearPDFRenderer([.slowSuccess])
        let model = try makeModel(renderer: renderer)

        let task = Task { await model.generate(isDemo: false) }
        try await waitUntil { model.progressFraction == 0.5 }
        let file = try #require(await task.value)

        #expect(model.state == .ready(file))
        #expect(file.pageCount == 2)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        try? FileManager.default.removeItem(at: file.storageDirectory)
    }

    @Test func cancellationReturnsToIdleAndDoesNotCreateAFile() async throws {
        let renderer = ScriptedYearPDFRenderer([.wait])
        let model = try makeModel(renderer: renderer)
        let task = Task { await model.generate(isDemo: false) }
        try await waitUntil { await renderer.started }

        task.cancel()
        #expect(await task.value == nil)
        #expect(model.state == .idle)
        #expect(await renderer.createdFiles.isEmpty)
    }

    @Test func cancellationWhileProgressDrainsPurgesTheCompletedFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let canceller = GenerationCanceller()
        let renderer = PostRenderCancellationRenderer(
            directory: directory,
            scheduleCancellation: {
                Task { @MainActor in
                    await Task.yield()
                    canceller.cancel()
                }
            },
        )
        let model = try makeModel(renderer: renderer)
        let task = Task { await model.generate(isDemo: false) }
        canceller.action = { task.cancel() }

        #expect(await task.value == nil)
        #expect(model.state == .idle)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test func failureCanBeAcknowledgedAndRetried() async throws {
        let renderer = ScriptedYearPDFRenderer([.failure, .success])
        let model = try makeModel(renderer: renderer)

        #expect(await model.generate(isDemo: false) == nil)
        #expect(model.state == .failed)
        #expect(model.isShowingFailure)
        model.isShowingFailure = false
        #expect(model.state == .idle)

        let file = try #require(await model.generate(isDemo: false))
        #expect(model.state == .ready(file))
        try? FileManager.default.removeItem(at: file.storageDirectory)
    }

    @Test func changingFormInputPurgesSupersededFileImmediately() async throws {
        let model = try makeModel(renderer: ScriptedYearPDFRenderer([.success]))
        let file = try #require(await model.generate(isDemo: false))
        #expect(FileManager.default.fileExists(atPath: file.url.path))

        model.reference = "Changed"

        #expect(model.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: file.storageDirectory.path))
    }

    @Test func successfulFileIsRetainedThenCleanedAfterDismissal() async throws {
        let model = try makeModel(
            renderer: ScriptedYearPDFRenderer([.success]),
            retention: .milliseconds(20),
        )
        let file = try #require(await model.generate(isDemo: true))

        model.sheetDidDismiss()
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        try await waitUntil {
            !FileManager.default.fileExists(atPath: file.storageDirectory.path)
        }
        #expect(model.state == .idle)
    }

    private func makeModel(
        renderer: any YearPDFRendering,
        retention: Duration = .seconds(600),
    ) throws -> YearExportModel {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        return YearExportModel(
            reader: services.reports,
            displayedYear: 2024,
            calendar: YearPDFTestSupport.calendar,
            locale: Locale(identifier: "en_US"),
            buildInfo: YearPDFTestSupport.buildInfo,
            now: { YearPDFTestSupport.date("2026-07-31T12:00:00-07:00") },
            renderer: renderer,
            retention: retention,
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () async -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Condition did not become true before timeout")
    }
}

private actor ScriptedYearPDFRenderer: YearPDFRendering {
    enum Behavior {
        case success
        case slowSuccess
        case failure
        case wait
    }

    private var behaviors: [Behavior]
    private(set) var started = false
    private(set) var createdFiles: [YearPDFFile] = []

    init(_ behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    func render(
        document: YearPDFDocument,
        progress: @escaping @Sendable (YearPDFProgress) -> Void,
    ) async throws -> YearPDFFile {
        started = true
        let behavior = behaviors.isEmpty ? .success : behaviors.removeFirst()
        switch behavior {
            case .failure:
                throw ScriptedFailure()
            case .wait:
                try await Task.sleep(for: .seconds(60))
                throw CancellationError()
            case .slowSuccess:
                progress(YearPDFProgress(completedPages: 1, totalPages: 2))
                try await Task.sleep(for: .milliseconds(50))
                return try makeFile(document: document, progress: progress)
            case .success:
                return try makeFile(document: document, progress: progress)
        }
    }

    private func makeFile(
        document: YearPDFDocument,
        progress: @escaping @Sendable (YearPDFProgress) -> Void,
    ) throws -> YearPDFFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.pdf")
        try Data("fixture".utf8).write(to: url)
        progress(YearPDFProgress(completedPages: 2, totalPages: 2))
        let prefix = document.isDemo ? "Where Demo Presence Report" : "Where Presence Report"
        let file = YearPDFFile(
            url: url,
            storageDirectory: directory,
            suggestedFilename: "\(prefix) 2024 fixture.pdf",
            pageCount: 2,
        )
        createdFiles.append(file)
        return file
    }
}

private struct ScriptedFailure: Error {}

@MainActor
private final class GenerationCanceller {
    var action: @MainActor @Sendable () -> Void = {}

    func cancel() {
        action()
    }
}

/// Runs on `generate`'s caller actor, queues cancellation behind the final
/// progress update, and returns a completed file before either queued task can
/// run. This deterministically exercises cancellation during progress drain.
private struct PostRenderCancellationRenderer: YearPDFRendering {
    let directory: URL
    let scheduleCancellation: @Sendable () -> Void

    func render(
        document _: YearPDFDocument,
        progress: @escaping @Sendable (YearPDFProgress) -> Void,
    ) async throws -> YearPDFFile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.pdf")
        try Data("fixture".utf8).write(to: url)
        progress(YearPDFProgress(completedPages: 1, totalPages: 1))
        scheduleCancellation()
        return YearPDFFile(
            url: url,
            storageDirectory: directory,
            suggestedFilename: "Where Presence Report fixture.pdf",
            pageCount: 1,
        )
    }
}
