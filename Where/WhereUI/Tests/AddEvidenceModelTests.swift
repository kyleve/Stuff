import Foundation
import Testing
import WhereCore
import WhereTesting
@testable import WhereUI

/// Covers `AddEvidenceModel`: how the form fields map into an `Evidence` value
/// (kind resolution, content-type classification, note trimming) and that a
/// save persists something the evidence reader can read back.
@MainActor
struct AddEvidenceModelTests {
    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    private static let fixedDate = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!

    private static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let pdfBytes = Data("%PDF-1.7".utf8)

    @Test func buildEvidenceClassifiesAttachmentAndTrimsNote() throws {
        // Read the main-actor constant here, then hand the `@Sendable` `now`
        // closure a captured local so it doesn't touch actor-isolated state.
        let fixedDate = Self.fixedDate
        let model = try AddEvidenceModel(services: makeServices(), now: { fixedDate })
        model.kind = .planeTicket
        model.note = "  boarding pass  "
        model.setAttachment(PickedAttachment(
            data: Self.pngBytes,
            typeIdentifier: nil,
            filename: "pass.png",
        ))

        let evidence = model.buildEvidence()

        #expect(evidence.kind == .planeTicket)
        #expect(evidence.contentType == .image)
        #expect(evidence.note == "boarding pass")
        #expect(evidence.capturedAt == Self.fixedDate)
        #expect(evidence.region == nil)
    }

    @Test func buildEvidenceFoldsOtherLabelIntoKind() throws {
        let model = try AddEvidenceModel(services: makeServices())
        model.kind = .other(nil)
        model.otherLabel = "  Ferry ticket  "

        #expect(model.buildEvidence().kind == .other("Ferry ticket"))
    }

    @Test func buildEvidenceWithoutAttachmentIsMetadataOnly() throws {
        let model = try AddEvidenceModel(services: makeServices())
        model.kind = .email

        let evidence = model.buildEvidence()

        #expect(evidence.contentType == .other(nil))
        #expect(evidence.note == nil)
    }

    @Test func savePersistsEvidenceAndBlobRetrievableByReader() async throws {
        let services = try makeServices()
        let fixedDate = Self.fixedDate
        let model = AddEvidenceModel(services: services, now: { fixedDate })
        model.kind = .document
        model.setAttachment(PickedAttachment(
            data: Self.pdfBytes,
            typeIdentifier: nil,
            filename: "receipt.pdf",
        ))

        let saved = await model.save()
        #expect(saved)

        let list = try await services.evidence.list(for: 2026)
        #expect(list.count == 1)
        #expect(list.first?.kind == .document)
        #expect(list.first?.contentType == .pdf)
        let blob = try #require(list.first).id
        #expect(try await services.evidence.blob(for: blob) == Self.pdfBytes)
    }
}
