import Foundation
import Testing
import WhereCore

struct WhereControllerTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private static func makeAggregator() -> DayAggregator {
        DayAggregator(calendar: Calendar(identifier: .gregorian), timeZone: pacific)
    }

    private static func makeController() throws
        -> (WhereController, SwiftDataStore, ScriptedLocationSource)
    {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let controller = WhereController(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
        )
        return (controller, store, source)
    }

    private static var pacificCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar
    }

    /// Build a controller with a spy scheduler and a frozen `now` so the
    /// reminder/badge reconciliation is deterministic.
    private static func makeReminderController(
        now: Date,
        scheduler: SpyReminderScheduler,
    ) throws -> (WhereController, SwiftDataStore, ScriptedLocationSource) {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let controller = WhereController(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
            reminderScheduler: scheduler,
            now: { now },
        )
        return (controller, store, source)
    }

    @Test func ingestStoresSamplesAndReportsThem() async throws {
        let (controller, _, _) = try Self.makeController()
        let sf = LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        )
        try await controller.ingest(sf)

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.days.first?.regions == [.california])
        #expect(report.totals == [.california: 1])
    }

    @Test func manualDayUnionsWithSamples() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await controller.addManualDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await controller.yearReport(for: 2026)
        let july4 = report.days.first { day in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
            let components = cal.dateComponents([.month, .day], from: day.date)
            return components.month == 7 && components.day == 4
        }
        #expect(july4?.regions == [.california, .newYork])
    }

    @Test func manualDayReplacesOnSecondCall() async throws {
        let (controller, _, _) = try Self.makeController()
        let date = iso("2026-07-04T15:00:00-07:00")
        try await controller.addManualDay(date: date, regions: [.california])
        try await controller.addManualDay(date: date, regions: [.newYork])

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        // Second call should replace, not union, when there are no
        // GPS samples on the day — proves the store-level upsert on
        // `setManualDay` (not a delete-then-insert that would let
        // duplicates accumulate).
        #expect(report.days.first?.regions == [.newYork])
    }

    @Test func overrideDayReplacesGPSAttribution() async throws {
        let (controller, _, _) = try Self.makeController()
        // A stray GPS sample lands the day in California.
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        ))
        // The user corrects it to New York.
        try await controller.overrideDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.days.first?.regions == [.newYork])
        #expect(report.totals == [.newYork: 1])
    }

    @Test func overrideDayKeepsRawSamplesForUndo() async throws {
        let (controller, store, _) = try Self.makeController()
        let stray = sample(at: "2026-07-04T10:00:00-07:00")
        try await controller.ingest(stray)
        try await controller.overrideDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        // The override is non-destructive: the GPS sample is still on disk, so
        // clearing the manual day would restore the original attribution.
        #expect(try await store.allSamples().map(\.id) == [stray.id])
    }

    @Test func clearManualDayRestoresGPSAttribution() async throws {
        let (controller, _, _) = try Self.makeController()
        // GPS puts the day in California.
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        ))
        // The user wrongly relabels it to New York, then resets to GPS.
        try await controller.overrideDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )
        try await controller.clearManualDay(date: iso("2026-07-04T15:00:00-07:00"))

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.first?.regions == [.california])
        #expect(report.totals == [.california: 1])
    }

    @Test func clearManualDayIsANoOpWithoutAManualRecord() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.clearManualDay(date: iso("2026-07-04T15:00:00-07:00"))

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.isEmpty)
    }

    @Test func additiveBackfillPreservesAnAuthoritativeRelabel() async throws {
        let (controller, _, _) = try Self.makeController()
        // GPS lands July 4 in California *and* New York (a stray cross-country hit).
        try await controller.ingest(sample(at: "2026-07-04T10:00:00-07:00"))
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-07-04T20:00:00-04:00"),
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            horizontalAccuracy: 5,
            source: .gpsVisit,
        ))
        // The user corrects the day to California only, removing the wrong NY hit.
        try await controller.overrideDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.california],
        )
        // A later range backfill (Canada) sweeps over the same corrected day.
        try await controller.addManualDays(
            from: iso("2026-07-01T00:00:00-07:00"),
            through: iso("2026-07-07T00:00:00-07:00"),
            regions: [.canada],
        )

        let report = try await controller.yearReport(for: 2026)
        let july4 = report.days.first {
            Self.pacificCalendar.isDate($0.date, inSameDayAs: iso("2026-07-04T12:00:00-07:00"))
        }
        // The relabel survives: New York stays removed (GPS is not resurrected)
        // and the backfilled Canada unions onto the corrected California.
        #expect(july4?.regions == [.california, .canada])
    }

    @Test func addManualDaysBackfillsEveryDayInRange() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.addManualDays(
            from: iso("2026-02-10T09:00:00-08:00"),
            through: iso("2026-02-14T20:00:00-08:00"),
            regions: [.newYork],
        )

        let report = try await controller.yearReport(for: 2026)
        // Feb 10–14 inclusive is five days, each attributed to New York.
        #expect(report.days.count == 5)
        #expect(report.totals == [.newYork: 5])
        #expect(report.days.allSatisfy { $0.regions == [.newYork] })
    }

    @Test func addManualDaysWithStartAfterEndWritesNothing() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.addManualDays(
            from: iso("2026-02-14T00:00:00-08:00"),
            through: iso("2026-02-10T00:00:00-08:00"),
            regions: [.california],
        )

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func addManualDaysSameStartAndEndWritesOneDay() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.addManualDays(
            from: iso("2026-02-10T06:00:00-08:00"),
            through: iso("2026-02-10T23:00:00-08:00"),
            regions: [.california],
        )

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.totals == [.california: 1])
    }

    @Test func clearYearWipesAndReportsEmpty() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await controller.clearYear(2026)
        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func gpsFailuresEnqueueAndDrainOnRecovery() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource()
        let controller = WhereController(
            store: store,
            locationSource: source,
            aggregator: Self.makeAggregator(),
        )
        await controller.startGPS()

        let sampleA = LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        let sampleB = LocationSample(
            timestamp: iso("2026-03-15T12:05:00-07:00"),
            coordinate: Coordinate(latitude: 37.7750, longitude: -122.4195),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        await store.setShouldFail(true)
        source.emit(sampleA)
        source.emit(sampleB)
        try await waitUntil { await controller.retryQueueDepth == 2 }
        #expect(await store.persistedCount == 0)

        await store.setShouldFail(false)
        let sampleC = LocationSample(
            timestamp: iso("2026-03-15T12:10:00-07:00"),
            coordinate: Coordinate(latitude: 37.7751, longitude: -122.4196),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        source.emit(sampleC)
        try await waitUntil { await controller.retryQueueDepth == 0 }
        #expect(await store.persistedCount == 3)

        await controller.stopGPS()
    }

    @Test func trackingResumesAfterPauseWithoutDroppingSamples() async throws {
        let (controller, _, source) = try Self.makeController()

        await controller.startGPS()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { try await controller.yearReport(for: 2026).days.count == 1 }

        // Pause, then resume. A naive implementation cancels the stream
        // consumer here, leaving the resumed session iterating a finished
        // stream so this second sample would be silently dropped.
        await controller.stopGPS()
        let pausedActive = await controller.isTrackingActive
        #expect(!pausedActive)
        await controller.startGPS()
        let resumedActive = await controller.isTrackingActive
        #expect(resumedActive)

        source.emit(sample(at: "2026-03-16T12:00:00-07:00"))
        try await waitUntil { try await controller.yearReport(for: 2026).days.count == 2 }

        await controller.stopGPS()
    }

    @Test func performThrow_rollsBackEntireTransaction() async throws {
        let store = try SwiftDataStore.inMemory()
        let s1 = sample(at: "2026-04-10T08:00:00-07:00")
        let s2 = sample(at: "2026-04-10T09:00:00-07:00")

        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.perform {
                try await store.add(sample: s1)
                try await store.add(sample: s2)
                throw Boom()
            }
        }

        let persisted = try await store.allSamples()
        #expect(persisted.isEmpty, "throwing perform should roll back every staged write")
    }

    @Test func performSuccess_writesAreVisibleToReadersAfterReturn() async throws {
        let store = try SwiftDataStore.inMemory()
        let s = sample(at: "2026-04-10T08:00:00-07:00")

        try await store.perform { try await store.add(sample: s) }

        let persisted = try await store.allSamples()
        #expect(persisted == [s], "saved peer changes should be visible to the main read context")
    }

    @Test func readsInsidePerform_seePendingWritesOnPeer() async throws {
        let store = try SwiftDataStore.inMemory()
        let s = sample(at: "2026-04-10T08:00:00-07:00")

        let countSeenInsidePerform = try await store.perform { () -> Int in
            try await store.add(sample: s)
            return try await store.allSamples().count
        }
        #expect(
            countSeenInsidePerform == 1,
            "in-flight peer writes should be readable inside the same perform",
        )
    }

    private func sample(at isoString: String) -> LocationSample {
        LocationSample(
            id: UUID(),
            timestamp: iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }

    @Test func evidenceRoundTripsViaController() async throws {
        let (controller, _, _) = try Self.makeController()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: iso("2026-04-10T08:00:00-07:00"),
            region: .california,
            note: "SFO → JFK",
            contentType: .plainText,
        )
        let blob = Data("ticket pdf".utf8)
        try await controller.addEvidence(evidence, blob: blob)

        let fetched = try await controller.evidence(for: 2026)
        #expect(fetched == [evidence])

        let fetchedBlob = try await controller.evidenceBlob(for: evidence.id)
        #expect(fetchedBlob == blob)
    }

    // MARK: - Backup

    private static let backupEvidence = Evidence(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .boardingPass,
        capturedAt: Date(timeIntervalSince1970: 1_700_050_000),
        region: .california,
        note: "SFO → JFK",
        contentType: .pdf,
    )
    private static let backupBlob = Data("boarding-pass-pdf".utf8)

    /// Seed a controller's store with one sample, one evidence (with a blob),
    /// and one manual day so backup tests have all three tables populated.
    private func seedBackupData(_ controller: WhereController) async throws {
        try await controller.ingest(sample(at: "2026-03-15T12:00:00-07:00"))
        try await controller.addEvidence(Self.backupEvidence, blob: Self.backupBlob)
        try await controller.addManualDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )
    }

    @Test func backupExportThenMergeImportReproducesEveryTable() async throws {
        let (source, sourceStore, _) = try Self.makeController()
        try await seedBackupData(source)

        let url = try await source.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeController()
        let summary = try await destination.importBackup(from: url, strategy: .merge)

        #expect(summary.sampleCount == 1)
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)

        #expect(try await destinationStore.allSamples() == sourceStore.allSamples())
        #expect(try await destinationStore.allEvidence() == sourceStore.allEvidence())
        #expect(try await destinationStore.allManualDays() == sourceStore.allManualDays())
        #expect(
            try await destinationStore.evidenceBlob(for: Self.backupEvidence.id) == Self.backupBlob,
        )
    }

    @Test func backupMergeImportKeepsPreexistingRows() async throws {
        let (source, _, _) = try Self.makeController()
        try await seedBackupData(source)
        let url = try await source.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeController()
        // A row that exists only on the destination and is absent from the
        // backup; merge must leave it in place.
        let preexisting = sample(at: "2026-01-01T09:00:00-08:00")
        try await destination.addManualSample(preexisting)

        _ = try await destination.importBackup(from: url, strategy: .merge)

        let ids = try await destinationStore.allSamples().map(\.id)
        #expect(ids.contains(preexisting.id))
        #expect(ids.count == 2)
    }

    @Test func backupReplaceImportWipesPreexistingRows() async throws {
        let (source, sourceStore, _) = try Self.makeController()
        try await seedBackupData(source)
        let url = try await source.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeController()
        // Pre-existing destination data that the backup does not contain.
        try await destination.addManualSample(sample(at: "2026-01-01T09:00:00-08:00"))
        try await destination.addManualDay(
            date: iso("2026-02-02T10:00:00-08:00"),
            regions: [.canada],
        )

        _ = try await destination.importBackup(from: url, strategy: .replace)

        // The store now mirrors the backup exactly — none of the pre-existing
        // rows survive.
        #expect(try await destinationStore.allSamples() == sourceStore.allSamples())
        #expect(try await destinationStore.allManualDays() == sourceStore.allManualDays())
    }

    @Test func clearAll_removesEveryTable() async throws {
        let store = try SwiftDataStore.inMemory()
        let seedSample = sample(at: "2026-03-15T12:00:00-07:00")
        let seedDay = DayPresence(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            regions: [.california],
        )
        try await store.perform {
            try await store.add(sample: seedSample)
            try await store.write(evidence: Self.backupEvidence, blob: Self.backupBlob)
            try await store.setManualDay(seedDay)
        }

        try await store.perform { try await store.clearAll() }

        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.allEvidence().isEmpty)
        #expect(try await store.allManualDays().isEmpty)
    }

    // MARK: - Logging reminders

    @Test func configureRemindersEnabledRequestsAuthAndBadgesTheBacklog() async throws {
        let now = iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, _) = try Self.makeReminderController(now: now, scheduler: spy)

        await controller.configureReminders(enabled: true, time: .defaultEvening)

        #expect(await spy.authorizationRequests == 1)
        #expect(await spy.lastEnabled == true)
        // Backlog is past misses only: Jan 1–4 (today, Jan 5, is still pending).
        #expect(await spy.lastBadgeCount == 4)
        // Rolling window is today + 6 days (Jan 5–11), all still unlogged.
        #expect(await spy.lastScheduleDays.count == 7)
        let today = Self.pacificCalendar.startOfDay(for: now)
        #expect(await spy.lastScheduleDays.contains(today))
    }

    @Test func configureRemindersDisabledClearsBadgeAndSchedulesNothing() async throws {
        let spy = SpyReminderScheduler()
        let (controller, _, _) = try Self.makeReminderController(
            now: iso("2026-01-05T09:00:00-08:00"),
            scheduler: spy,
        )

        await controller.configureReminders(enabled: false, time: .defaultEvening)

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
        #expect(await spy.lastBadgeCount == 0)
        #expect(await spy.lastScheduleDays.isEmpty)
    }

    @Test func loggingTodayViaGPSCancelsItsScheduledReminder() async throws {
        let now = iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, source) = try Self.makeReminderController(now: now, scheduler: spy)
        await controller.configureReminders(enabled: true, time: .defaultEvening)

        let today = Self.pacificCalendar.startOfDay(for: now)
        // Today is a forward nudge, not part of the backlog (Jan 1–4 = 4 days).
        #expect(await spy.lastBadgeCount == 4)
        #expect(await spy.lastScheduleDays.contains(today))

        await controller.startGPS()
        source.emit(LocationSample(
            timestamp: iso("2026-01-05T12:00:00-08:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))

        // Logging today removes today's reminder; the past backlog is unchanged.
        try await waitUntil { await !spy.lastScheduleDays.contains(today) }
        #expect(await spy.lastBadgeCount == 4)

        await controller.stopGPS()
    }

    @Test func loggingPastDayViaGPSAfterTodayIsCoveredStillReconciles() async throws {
        let now = iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, source) = try Self.makeReminderController(now: now, scheduler: spy)
        await controller.configureReminders(enabled: true, time: .defaultEvening)

        await controller.startGPS()
        source.emit(LocationSample(
            timestamp: iso("2026-01-05T12:00:00-08:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))
        try await waitUntil { await spy.lastBadgeCount == 4 }

        // Visits can arrive late with their original timestamp. Even after the
        // controller knows today is covered, filling a past gap must lower the
        // backlog badge.
        source.emit(LocationSample(
            timestamp: iso("2026-01-03T12:00:00-08:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        ))

        try await waitUntil { await spy.lastBadgeCount == 3 }

        await controller.stopGPS()
    }

    @Test func manualDayLoggingAPastDayLowersTheBadge() async throws {
        let now = iso("2026-03-10T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, _) = try Self.makeReminderController(now: now, scheduler: spy)
        await controller.configureReminders(enabled: true, time: .defaultEvening)

        // Backlog is Jan 1 – Mar 9 (today, Mar 10, is excluded): 68 days of 2026.
        #expect(await spy.lastBadgeCount == 68)

        try await controller.addManualDay(
            date: iso("2026-03-03T12:00:00-08:00"),
            regions: [.california],
        )

        #expect(await spy.lastBadgeCount == 67)
    }

    @Test func clearCurrentYearReconcilesTheBadge() async throws {
        let now = iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, _) = try Self.makeReminderController(now: now, scheduler: spy)
        await controller.configureReminders(enabled: true, time: .defaultEvening)

        try await controller.addManualDay(
            date: iso("2026-01-01T12:00:00-08:00"),
            regions: [.california],
        )
        // Backlog (Jan 1–4) minus the logged Jan 1 leaves 3.
        #expect(await spy.lastBadgeCount == 3)

        try await controller.clearYear(2026)

        // Clearing puts all four past days back into the backlog.
        #expect(await spy.lastBadgeCount == 4)
    }

    @Test func changingReminderTimeReconcilesWithTheNewTime() async throws {
        let now = iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, _) = try Self.makeReminderController(now: now, scheduler: spy)

        await controller.configureReminders(enabled: true, time: .defaultEvening)
        await controller.configureReminders(enabled: true, time: ReminderTime(hour: 7, minute: 30))

        #expect(await spy.authorizationRequests == 2)
        #expect(await spy.reconcileCount == 2)
        #expect(await spy.lastReminderTime == ReminderTime(hour: 7, minute: 30))
        #expect(await spy.lastBadgeCount == 4)
    }

    @Test func disablingRemindersAfterEnablingClearsEverything() async throws {
        let now = iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (controller, _, _) = try Self.makeReminderController(now: now, scheduler: spy)

        await controller.configureReminders(enabled: true, time: .defaultEvening)
        #expect(await spy.lastBadgeCount == 4)

        await controller.configureReminders(enabled: false, time: .defaultEvening)
        #expect(await spy.lastEnabled == false)
        #expect(await spy.lastBadgeCount == 0)
        #expect(await spy.lastScheduleDays.isEmpty)
    }

    // MARK: - Widget timeline refresh

    private static func makeWidgetController(
        refresher: SpyWidgetRefresher,
        store: (any WhereStore)? = nil,
    ) throws -> (WhereController, ScriptedLocationSource) {
        let source = ScriptedLocationSource()
        let controller = try WhereController(
            store: store ?? SwiftDataStore.inMemory(),
            locationSource: source,
            aggregator: makeAggregator(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: refresher,
        )
        return (controller, source)
    }

    @Test func committedWritesReloadWidgetTimelines() async throws {
        let refresher = SpyWidgetRefresher()
        let (controller, _) = try Self.makeWidgetController(refresher: refresher)

        try await controller.ingest(sample(at: "2026-03-15T12:00:00-07:00"))
        #expect(await refresher.reloadCount == 1)

        let day = iso("2026-07-04T15:00:00-07:00")
        try await controller.addManualDay(date: day, regions: [.newYork])
        try await controller.overrideDay(date: day, regions: [.california])
        try await controller.clearManualDay(date: day)
        try await controller.clearYear(2026)
        #expect(await refresher.reloadCount == 5)
    }

    @Test func gpsIngestReloadsWidgetTimelines() async throws {
        let refresher = SpyWidgetRefresher()
        let (controller, source) = try Self.makeWidgetController(refresher: refresher)

        await controller.startGPS()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await refresher.reloadCount == 1 }

        await controller.stopGPS()
    }

    @Test func failedGPSPersistSkipsWidgetReloadUntilRetrySucceeds() async throws {
        let refresher = SpyWidgetRefresher()
        let store = try ToggleFailingStore(backing: SwiftDataStore.inMemory())
        let (controller, source) = try Self.makeWidgetController(
            refresher: refresher,
            store: store,
        )

        await controller.startGPS()
        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await controller.retryQueueDepth == 1 }
        // Nothing was committed, so the widgets have nothing new to show.
        #expect(await refresher.reloadCount == 0)

        // The next successful persist drains the backlog and repaints.
        await store.setShouldFail(false)
        source.emit(sample(at: "2026-03-15T12:10:00-07:00"))
        try await waitUntil { await refresher.reloadCount == 1 }

        await controller.stopGPS()
    }
}

private func iso(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: string) ?? Date(timeIntervalSince1970: 0)
}

@Sendable
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () async throws -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("waitUntil timed out")
}

/// Records the calls `WhereController` makes to the reminder scheduler so
/// tests can assert the badge count, scheduled days, and enabled state without
/// touching `UNUserNotificationCenter`.
private actor SpyReminderScheduler: LoggingReminderScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastBadgeCount: Int?
    private(set) var lastScheduleDays: [Date] = []
    private(set) var lastReminderTime: ReminderTime?
    private(set) var lastEnabled: Bool?
    private let authorized: Bool

    init(authorized: Bool = true) {
        self.authorized = authorized
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorized
    }

    func isAuthorized() async -> Bool {
        authorized
    }

    func reconcile(
        badgeCount: Int,
        scheduleDays: [Date],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        reconcileCount += 1
        lastBadgeCount = badgeCount
        lastScheduleDays = scheduleDays
        lastReminderTime = reminderTime
        lastEnabled = enabled
    }
}

/// Counts the reload requests `WhereController` sends to WidgetKit so tests
/// can assert widgets repaint after committed writes — and stay untouched
/// when a write fails.
private actor SpyWidgetRefresher: WidgetTimelineRefreshing {
    private(set) var reloadCount = 0

    func reloadTimelines() async {
        reloadCount += 1
    }
}

private struct ToggleFailingStoreError: Error {}

/// `WhereStore` that lets a test toggle whether `add(sample:)` succeeds.
/// Every other API forwards to a real `SwiftDataStore` (in-memory) so
/// reads stay deterministic and the failure injection point stays
/// narrow.
private actor ToggleFailingStore: WhereStore {
    private let backing: SwiftDataStore
    private var shouldFail = false

    init(backing: SwiftDataStore) {
        self.backing = backing
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    var persistedCount: Int {
        get async {
            await (try? backing.allSamples().count) ?? 0
        }
    }

    func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        try await backing.perform(block)
    }

    func add(sample: LocationSample) async throws {
        if shouldFail { throw ToggleFailingStoreError() }
        try await backing.add(sample: sample)
    }

    func samples(in interval: DateInterval) async throws -> [LocationSample] {
        try await backing.samples(in: interval)
    }

    func allSamples() async throws -> [LocationSample] {
        try await backing.allSamples()
    }

    func write(evidence: Evidence, blob: Data?) async throws {
        try await backing.write(evidence: evidence, blob: blob)
    }

    func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await backing.evidence(in: interval)
    }

    func allEvidence() async throws -> [Evidence] {
        try await backing.allEvidence()
    }

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await backing.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        try await backing.setManualDay(day)
    }

    func clearManualDay(_ date: Date) async throws {
        try await backing.clearManualDay(date)
    }

    func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        try await backing.manualDays(in: interval)
    }

    func allManualDays() async throws -> [DayPresence] {
        try await backing.allManualDays()
    }

    func clear(in interval: DateInterval) async throws {
        try await backing.clear(in: interval)
    }

    func clearAll() async throws {
        try await backing.clearAll()
    }
}
