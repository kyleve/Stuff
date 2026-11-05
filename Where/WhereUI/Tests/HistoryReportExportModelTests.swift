import Foundation
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct HistoryReportExportModelTests {
    @Test func unresolvedExportRequiresReviewAndDoesNotResumeWhenReviewCloses() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = HistoryReportExportTestSupport.model(fixture, year: 2026)
        model.requestExport()
        try await model.prepare(#require(model.requestID))
        guard case let .needsReview(completeness) = model.state else {
            Issue.record("Expected review before export"); return
        }
        #expect(!completeness.isComplete)
        #expect(model.state.export == nil)
        model.showingReview = true
        model.showingReview = false
        #expect(model.requestID == nil)
        #expect(!model.isPresentingExporter)
        #expect(model.canExport)

        let unaffected = HistoryReportExportTestSupport.model(fixture, year: 2027)
        unaffected.requestExport()
        try await unaffected.prepare(#require(unaffected.requestID))
        let export = try #require(unaffected.state.export)
        #expect(try export.document
            .exportedData() == Data("calendar_day,region_id,region_name\r\n".utf8))
    }

    @Test func systemDismissalRetainsIdentityUntilCompletionAndRejectsStaleCallbacks() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let model = HistoryReportExportTestSupport.model(fixture, year: 2026)
        model.requestExport()
        try await model.prepare(#require(model.requestID))
        let first = try #require(model.state.export)
        model.isPresentingExporter = false
        #expect(!model.canExport)
        #expect(model.state.export?.id == first.id)
        model.cancelExport(first.id)
        #expect(throws: HistoryReportDocument.ExportError.retired) {
            try first.document.exportedData()
        }
        model.requestExport()
        try await model.prepare(#require(model.requestID))
        let second = try #require(model.state.export)
        model.complete(.failure(FailedHistoryReportSource.Failure.unavailable), requestID: first.id)
        model.cancelExport(first.id)
        #expect(model.state.export?.id == second.id)
        model.complete(.success(URL(fileURLWithPath: "/tmp/history.csv")), requestID: second.id)
        guard case .saved = model.state else { Issue.record("Expected saved result"); return }
        #expect(throws: HistoryReportDocument.ExportError.retired) {
            try second.document.exportedData()
        }
    }

    @Test(arguments: [false, true])
    func cancelledOrRetiredPreparationCannotPublish(_ retire: Bool) async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let source = try await HeldHistoryReportSource(report: fixture.services.reports
            .exportableYearCSV(for: 2026))
        let model = HistoryReportExportModel(
            source: source,
            validate: fixture.services.validateDataAccess,
            year: 2026,
            isAvailable: true,
        )
        model.requestExport()
        let requestID = try #require(model.requestID)
        let task = Task { await model.prepare(requestID) }
        await source.waitUntilEntered()
        if retire { model.deactivate() } else { task.cancel(); model.cancelPreparation() }
        await source.release()
        await task.value
        #expect(model.state.export == nil)
        #expect(!model.isPresentingExporter)
        model.requestExport()
        #expect((model.requestID == nil) == retire)
    }

    @Test func revocationDuringPreparationWinsOverTheCompletedRead() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let source = try await HeldHistoryReportSource(report: fixture.services.reports
            .exportableYearCSV(for: 2026))
        let model = HistoryReportExportModel(
            source: source,
            validate: fixture.services.validateDataAccess,
            year: 2026,
            isAvailable: true,
        )
        model.requestExport()
        let requestID = try #require(model.requestID)
        let task = Task { await model.prepare(requestID) }
        await source.waitUntilEntered()
        await fixture.services.retireCompatibilityScope()
        await source.release()
        await task.value
        guard case let .failed(error) = model.state
        else { Issue.record("Expected revoked failure"); return }
        #expect(error as? DataCompatibilityAccess.AccessError == .revoked)
        #expect(!model.isPresentingExporter)
    }

    @Test func failureRemainsObservableAndDisabledContractsCannotStart() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let model = HistoryReportExportModel(
            source: FailedHistoryReportSource(),
            validate: fixture.services.validateDataAccess,
            year: 2026,
            isAvailable: true,
        )
        model.requestExport()
        try await model.prepare(#require(model.requestID))
        guard case let .failed(error) = model.state
        else { Issue.record("Expected read failure"); return }
        #expect(error as? FailedHistoryReportSource.Failure == .unavailable)
        #expect(model.canExport)
        let disabled = HistoryReportExportModel(
            source: FailedHistoryReportSource(),
            validate: fixture.services.validateDataAccess,
            year: 2026,
            isAvailable: false,
        )
        disabled.requestExport()
        #expect(disabled.requestID == nil)
        #expect(!disabled.canExport)
    }

    @Test func ownerReleaseRetiresAReadyDocument() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        var model: HistoryReportExportModel? = HistoryReportExportTestSupport.model(
            fixture,
            year: 2026,
        )
        model?.requestExport()
        try await model?.prepare(#require(model?.requestID))
        let document = try #require(model?.state.export?.document)
        model = nil
        #expect(throws: HistoryReportDocument.ExportError.retired) { try document.exportedData() }
    }

    @Test func supersededReadCannotReplaceTheNewExport() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let source = try await HeldHistoryReportSource(report: fixture.services.reports
            .exportableYearCSV(for: 2026))
        let model = HistoryReportExportModel(
            source: source,
            validate: fixture.services.validateDataAccess,
            year: 2026,
            isAvailable: true,
        )
        model.requestExport()
        let previous = try #require(model.requestID)
        let task = Task { await model.prepare(previous) }
        await source.waitUntilEntered()
        model.cancelPreparation()
        model.requestExport()
        let current = try #require(model.requestID)
        await model.prepare(current)
        #expect(model.state.export?.id == current)
        await source.release()
        await task.value
        #expect(model.state.export?.id == current)
    }
}
