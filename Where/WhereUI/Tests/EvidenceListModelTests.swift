import Foundation
import Testing
import WhereCore
import WhereTesting
@testable import WhereUI

/// Covers `EvidenceListModel`'s mapping of the year's evidence into a
/// `LoadState`, against an in-memory store.
@MainActor
struct EvidenceListModelTests {
    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func loadEmptyYearIsEmptyState() async throws {
        let services = try makeServices()
        let model = EvidenceListModel(services: services)

        await model.load(for: 2026)

        #expect(model.loadState == .empty)
    }

    @Test func loadReturnsThisYearsEvidence() async throws {
        let services = try makeServices()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: Self.date(2026, 3, 4),
            contentType: .pdf,
        )
        try await services.journal.addEvidence(evidence, blob: nil)
        let model = EvidenceListModel(services: services)

        await model.load(for: 2026)

        #expect(model.loadState == .loaded([evidence]))
    }

    @Test func loadExcludesOtherYears() async throws {
        let services = try makeServices()
        try await services.journal.addEvidence(
            Evidence(kind: .document, capturedAt: Self.date(2025, 5, 1), contentType: .pdf),
            blob: nil,
        )
        let model = EvidenceListModel(services: services)

        await model.load(for: 2026)

        #expect(model.loadState == .empty)
    }
}
