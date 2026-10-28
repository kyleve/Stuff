import Foundation
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Covers `EvidenceDetailModel`'s blob load, distinguishing a stored attachment
/// from an attachment-less record.
@MainActor
struct EvidenceDetailModelTests {
    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    private static let captured = Date(timeIntervalSince1970: 1_770_000_000)

    @Test func loadReturnsStoredBlob() async throws {
        let services = try makeServices()
        let blob = Data("%PDF-1.7".utf8)
        let evidence = Evidence(kind: .document, capturedAt: Self.captured, contentType: .pdf)
        try await services.journal.addEvidence(evidence, blob: blob)
        let model = EvidenceDetailModel(evidence: evidence, services: services)

        await model.load()

        #expect(model.blobState == .loaded(blob))
    }

    @Test func loadWithNoAttachmentIsLoadedNil() async throws {
        let services = try makeServices()
        let evidence = Evidence(kind: .email, capturedAt: Self.captured, contentType: .plainText)
        try await services.journal.addEvidence(evidence, blob: nil)
        let model = EvidenceDetailModel(evidence: evidence, services: services)

        await model.load()

        #expect(model.blobState == .loaded(nil))
    }
}
