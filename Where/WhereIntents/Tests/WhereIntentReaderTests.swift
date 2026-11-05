import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereIntents

/// The read seam the query intents delegate to, driven against an in-memory
/// store seeded through `DayJournal`.
struct WhereIntentReaderTests {
    @Test func retiredServicesCannotAnswerToday() async throws {
        let fixture = try await CompatibilityIntentFixture()
        fixture.access.revoke()
        await #expect(throws: (any Error).self) {
            try await reader(fixture.services).todayRegions()
        }
    }

    @Test @MainActor func unresolvedDateWithholdsYearAndDayAnswersUntilAChoiceResolvesIt(
    ) async throws {
        let fixture = try await RecordingIntentFixture(calendar: IntentTestSupport.calendar())
        try await fixture.addConflict()
        let reader = reader(fixture.services, now: { RecordingIntentFixture.epoch })
        await #expect(throws: IntentHistoryReviewError.self) { try await reader.dayCount(
            in: .california,
            year: 2026,
        ) }
        await #expect(throws: IntentHistoryReviewError.self) {
            try await reader.regions(on: RecordingIntentFixture.epoch)
        }
        await #expect(throws: IntentHistoryReviewError.self) { try await reader.todayRegions() }
        // An unrelated date and year remain answerable, including an honestly empty day.
        let clearDay = IntentTestSupport.iso("2026-06-10T12:00:00Z")
        #expect(try await reader.regions(on: clearDay).isEmpty)
        #expect(try await reader.dayCount(in: .california, year: 2025) == 0)
        try await fixture.selectFirst()
        #expect(try await reader.dayCount(in: .california, year: 2026) == 1)
        let todayRegions = try await reader.todayRegions()
        #expect(todayRegions == [.california])
    }

    @Test @MainActor func manualPresenceCannotHideUnresolvedRecordingHistory() async throws {
        let fixture = try await RecordingIntentFixture(calendar: IntentTestSupport.calendar())
        try await fixture.addConflict()
        try await fixture.store.perform { [store = fixture.store] in
            try await store.setManualDay(.init(
                day: .init(year: 2026, month: 6, day: 15),
                regions: [.canada],
                isAuthoritative: true,
            ))
        }
        let reader = reader(fixture.services)
        await #expect(throws: IntentHistoryReviewError.self) { try await reader.dayCount(
            in: .canada,
            year: 2026,
        ) }
        await #expect(throws: IntentHistoryReviewError.self) {
            try await reader.regions(on: RecordingIntentFixture.epoch)
        }
    }

    private func reader(_ services: WhereServices, now: @escaping @Sendable () -> Date = { Date() })
        -> WhereIntentReader
    {
        WhereIntentReader(services: services, calendar: IntentTestSupport.calendar(), now: now)
    }

    @Test func dayCountReflectsYearReportTotals() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        try await services.journal.addManualDay(
            date: IntentTestSupport.iso("2026-03-01T12:00:00-08:00"),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: IntentTestSupport.iso("2026-03-02T12:00:00-08:00"),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: IntentTestSupport.iso("2026-03-03T12:00:00-08:00"),
            regions: [.newYork],
            audit: nil,
        )

        let reader = reader(services)
        #expect(try await reader.dayCount(in: .california, year: 2026) == 2)
        #expect(try await reader.dayCount(in: .newYork, year: 2026) == 1)
        #expect(try await reader.dayCount(in: .canada, year: 2026) == 0)
    }

    @Test func regionsOnDateReturnsThatDaysRegions() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let day = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        try await services.journal.addManualDay(
            date: day,
            regions: [.california, .newYork],
            audit: nil,
        )

        let regions = try await reader(services).regions(on: day)
        #expect(regions == [.california, .newYork])
    }

    @Test func regionsOnAnUnloggedDayAreEmpty() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let regions = try await reader(services)
            .regions(on: IntentTestSupport.iso("2026-06-15T12:00:00-07:00"))
        #expect(regions.isEmpty)
    }

    @Test func todayRegionsReadsCurrentHistoryAfterEachWrite() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let today = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        let reader = reader(services, now: { today })
        #expect(try await reader.todayRegions().isEmpty)
        try await services.journal.addManualDay(date: today, regions: [.california], audit: nil)
        let todayRegions = try await reader.todayRegions()
        #expect(todayRegions == [.california])
        try await services.journal.addManualDay(date: today, regions: [.newYork], audit: nil)
        let updated = try await reader.todayRegions()
        #expect(updated == [.newYork])
    }

    @Test @MainActor func recordedDaySurvivesViewerZoneAndYearChanges() async throws {
        let recordedAt = IntentTestSupport.iso("2026-01-01T00:30:00Z")
        let recordingZone = try #require(TimeZone(secondsFromGMT: -3600))
        for hours in [-12, 0, 14] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: hours * 3600))
            let fixture = try await RecordingIntentFixture(calendar: calendar)
            try await fixture.store.perform { [store = fixture.store] in
                try await store.add(sample: LocationSample(
                    timestamp: recordedAt,
                    coordinate: .init(latitude: 37.78, longitude: -122.42),
                    horizontalAccuracy: 10,
                    source: .gpsSignificantChange,
                    recordingDeviceID: RecordingIntentFixture.first,
                    recordingDay: .resolved(.init(observedAt: recordedAt, timeZone: recordingZone)),
                ))
            }
            let day = CalendarDay(year: 2025, month: 12, day: 31)
            let date = try day.startOfDay(in: calendar)
            let reader = WhereIntentReader(
                services: fixture.services,
                calendar: calendar,
                now: { date },
            )
            #expect(try await reader.dayCount(in: .california, year: 2025) == 1)
            #expect(try await reader.dayCount(in: .california, year: 2026) == 0)
            #expect(try await reader.regions(on: date) == [.california])
            let todayRegions = try await reader.todayRegions()
            #expect(todayRegions == [.california])
        }
    }

    @Test @MainActor func unknownRecordingDayRequiresInputBeforeAnswering() async throws {
        let fixture = try await RecordingIntentFixture(calendar: IntentTestSupport.calendar())
        try await fixture.store.perform { [store = fixture.store] in
            try await store.add(sample: LocationSample(
                timestamp: RecordingIntentFixture.epoch,
                coordinate: .init(latitude: 37.78, longitude: -122.42),
                horizontalAccuracy: 10,
                source: .gpsSignificantChange,
                recordingDeviceID: RecordingIntentFixture.first,
                recordingDay: .unresolved,
            ))
        }
        let reader = reader(fixture.services, now: { RecordingIntentFixture.epoch })
        let error = try #require(await #expect(throws: IntentHistoryReviewError.self) {
            try await reader.todayRegions()
        })
        #expect(error.underlyingError.completeness.hasUnassignedDays)
        #expect(error.errorDescription == IntentStrings.historyNeedsReview)
        await #expect(throws: IntentHistoryReviewError.self) { try await reader.dayCount(
            in: .california,
            year: 2026,
        ) }
    }
}
