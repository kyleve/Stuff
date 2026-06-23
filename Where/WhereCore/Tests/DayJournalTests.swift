import Foundation
import Testing
@testable import WhereCore

/// Covers the user-sourced writes (ingest, manual-day overlays, range
/// backfills, clears, evidence) and the reminder reconcile + widget publish
/// each one fans out to — the work the controller delegates to `DayJournal`.
struct DayJournalTests {
    private struct Harness {
        let journal: DayJournal
        let store: SwiftDataStore
        let reader: ReportReader
        let reminders: SpyReminderScheduler
        let widgets: SpyRefresher
    }

    private actor SpyRefresher: WidgetTimelineRefreshing {
        private(set) var publishCount = 0
        func publish(_: WidgetSnapshot) async {
            publishCount += 1
        }
    }

    private actor SpyReminderScheduler: LoggingReminderScheduling {
        private(set) var reconcileCount = 0
        private(set) var lastBadgeCount: Int?
        private(set) var lastEnabled: Bool?

        func requestAuthorization() async -> Bool {
            true
        }

        func isAuthorized() async -> Bool {
            true
        }

        func reconcile(
            badgeCount: Int,
            scheduleDays _: [Date],
            reminderTime _: ReminderTime,
            enabled: Bool,
        ) async {
            reconcileCount += 1
            lastBadgeCount = badgeCount
            lastEnabled = enabled
        }
    }

    private static func makeHarness(now: @escaping @Sendable () -> Date = { Date() }) throws
        -> Harness
    {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(store: store, aggregator: aggregator, attributor: .shared)
        let reminderSpy = SpyReminderScheduler()
        let reminders = ReminderReconciler(
            scheduler: reminderSpy,
            reportReader: reader,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
        let refresher = SpyRefresher()
        let widgets = WidgetSnapshotPublisher(
            widgetReader: WidgetDataReader(
                store: store,
                aggregator: aggregator,
                attributor: .shared,
            ),
            widgetRefresher: refresher,
            attributor: .shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
        let journal = DayJournal(
            store: store,
            aggregator: aggregator,
            reminders: reminders,
            widgets: widgets,
        )
        return Harness(
            journal: journal,
            store: store,
            reader: reader,
            reminders: reminderSpy,
            widgets: refresher,
        )
    }

    @Test func ingestPersistsAndPublishesOnce() async throws {
        let h = try Self.makeHarness(now: { WhereCoreTestSupport.iso("2026-03-15T20:00:00-07:00") })
        try await h.journal.ingest(sample(at: "2026-03-15T12:00:00-07:00"))

        let report = try await h.reader.yearReport(for: 2026)
        #expect(report.totals == [.california: 1])
        #expect(await h.widgets.publishCount == 1)
    }

    @Test func bulkIngestPersistsEverySampleAndPublishesOnce() async throws {
        let h = try Self.makeHarness()
        try await h.journal.ingest([
            sample(at: "2026-01-10T12:00:00-08:00"),
            sample(at: "2026-01-11T12:00:00-08:00"),
            LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-02-01T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ),
        ])

        let report = try await h.reader.yearReport(for: 2026)
        #expect(report.totals == [.california: 2, .newYork: 1])
        #expect(await h.widgets.publishCount == 1)
    }

    @Test func emptyBulkIngestIsANoOp() async throws {
        let h = try Self.makeHarness()
        try await h.journal.ingest([LocationSample]())

        #expect(try await h.reader.yearReport(for: 2026).days.isEmpty)
        #expect(await h.widgets.publishCount == 0)
    }

    @Test func addManualDayReconcilesAndPublishes() async throws {
        let h = try Self.makeHarness(now: { WhereCoreTestSupport.iso("2026-03-15T09:00:00-07:00") })
        try await h.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-03-03T12:00:00-08:00"),
            regions: [.newYork],
        )

        let report = try await h.reader.yearReport(for: 2026)
        #expect(report.totals == [.newYork: 1])
        #expect(await h.reminders.reconcileCount == 1)
        #expect(await h.widgets.publishCount == 1)
    }

    @Test func overrideDayReplacesGPSButKeepsRawSamples() async throws {
        let h = try Self.makeHarness()
        let stray = sample(at: "2026-07-04T10:00:00-07:00")
        try await h.journal.ingest(stray)
        try await h.journal.overrideDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await h.reader.yearReport(for: 2026)
        #expect(report.days.first?.regions == [.newYork])
        // Non-destructive: the GPS sample stays on disk so the override is undoable.
        #expect(try await h.store.allSamples().map(\.id) == [stray.id])
    }

    @Test func clearManualDayRestoresGPSAttribution() async throws {
        let h = try Self.makeHarness()
        try await h.journal.ingest(sample(at: "2026-07-04T10:00:00-07:00"))
        try await h.journal.overrideDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )
        try await h.journal
            .clearManualDay(date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"))

        let report = try await h.reader.yearReport(for: 2026)
        #expect(report.days.first?.regions == [.california])
    }

    @Test func addManualDaysBackfillsEveryDayInRange() async throws {
        let h = try Self.makeHarness()
        try await h.journal.addManualDays(
            from: WhereCoreTestSupport.iso("2026-02-10T09:00:00-08:00"),
            through: WhereCoreTestSupport.iso("2026-02-14T20:00:00-08:00"),
            regions: [.newYork],
        )

        let report = try await h.reader.yearReport(for: 2026)
        #expect(report.days.count == 5)
        #expect(report.totals == [.newYork: 5])
    }

    @Test func addManualDaysWithStartAfterEndWritesNothing() async throws {
        let h = try Self.makeHarness()
        try await h.journal.addManualDays(
            from: WhereCoreTestSupport.iso("2026-02-14T00:00:00-08:00"),
            through: WhereCoreTestSupport.iso("2026-02-10T00:00:00-08:00"),
            regions: [.california],
        )

        #expect(try await h.reader.yearReport(for: 2026).days.isEmpty)
        #expect(await h.widgets.publishCount == 0)
    }

    @Test func clearYearWipesAndReconciles() async throws {
        let h = try Self.makeHarness(now: { WhereCoreTestSupport.iso("2026-03-15T09:00:00-07:00") })
        try await h.journal.ingest(sample(at: "2026-03-15T12:00:00-07:00"))
        try await h.journal.clearYear(2026)

        #expect(try await h.reader.yearReport(for: 2026).days.isEmpty)
        #expect(await h.reminders.reconcileCount == 1)
    }

    @Test func eraseAllDataWipesEveryYearAndReconciles() async throws {
        let h = try Self.makeHarness(now: { WhereCoreTestSupport.iso("2026-03-15T09:00:00-07:00") })
        for year in [2024, 2025, 2026] {
            try await h.journal.ingest(sample(at: "\(year)-03-15T12:00:00-07:00"))
        }
        try await h.journal.eraseAllData()

        for year in [2024, 2025, 2026] {
            #expect(try await h.reader.yearReport(for: year).days.isEmpty)
        }
        #expect(await h.reminders.reconcileCount == 1)
    }

    @Test func evidenceRoundTrips() async throws {
        let h = try Self.makeHarness()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: WhereCoreTestSupport.iso("2026-04-10T08:00:00-07:00"),
            region: .california,
            note: "SFO → JFK",
            contentType: .plainText,
        )
        let blob = Data("ticket pdf".utf8)
        try await h.journal.addEvidence(evidence, blob: blob)

        #expect(try await h.journal.evidence(for: 2026) == [evidence])
        #expect(try await h.journal.evidenceBlob(for: evidence.id) == blob)
    }

    private func sample(at isoString: String) -> LocationSample {
        LocationSample(
            id: UUID(),
            timestamp: WhereCoreTestSupport.iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }
}
