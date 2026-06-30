import Foundation
import Testing
import WhereCore

/// Integration coverage for the assembled `WhereServices`: the cross-collaborator
/// wiring that no single focused suite owns — the ingestor's post-persist hook
/// fanning out to reminders + widgets, the exact backlog/badge math across the
/// journal + report reader + reminder reconciler, the daily-summary recap body,
/// and the `reset()` teardown. The per-collaborator suites (DayJournalTests,
/// BackupCoordinatorTests, ReminderReconcilerTests, …) cover each piece in
/// isolation; these prove they work together once `WhereServices` glues them up.
struct WhereServicesTests {
    private static func makeAggregator() -> DayAggregator {
        DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
    }

    private static func makeServices() throws
        -> (WhereServices, SwiftDataStore, ScriptedLocationSource)
    {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let services = WhereServices(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
        )
        return (services, store, source)
    }

    private static var pacificCalendar: Calendar {
        WhereCoreTestSupport.calendar()
    }

    /// Build services with a spy scheduler and a frozen `now` so the
    /// reminder/badge reconciliation is deterministic.
    private static func makeReminderServices(
        now: Date,
        scheduler: SpyReminderScheduler,
    ) throws -> (WhereServices, SwiftDataStore, ScriptedLocationSource) {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let services = WhereServices(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
            reminderScheduler: scheduler,
            now: { now },
        )
        return (services, store, source)
    }

    /// Build services with a spy daily-summary scheduler and a frozen `now`
    /// so the recap reconciliation is deterministic.
    private static func makeSummaryServices(
        now: Date,
        scheduler: SpyDailySummaryScheduler,
    ) throws -> (WhereServices, SwiftDataStore, ScriptedLocationSource) {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let services = WhereServices(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: scheduler,
            now: { now },
        )
        return (services, store, source)
    }

    @Test func ingestStoresSamplesAndReportsThem() async throws {
        let (services, _, _) = try Self.makeServices()
        let sf = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        )
        try await services.journal.ingest(sf)

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.days.first?.regions == [.california])
        #expect(report.totals == [.california: 1])
    }

    @Test func batchIngestPersistsEverySampleInOneTransaction() async throws {
        let (services, _, _) = try Self.makeServices()
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let nyc = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let samples = [
            LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-10T12:00:00-08:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ),
            LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-11T12:00:00-08:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ),
            LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-02-01T12:00:00-08:00"),
                coordinate: nyc,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ),
        ]
        try await services.journal.ingest(samples)

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.count == 3)
        #expect(report.totals == [.california: 2, .newYork: 1])
    }

    @Test func batchIngestOfEmptyArrayIsANoOp() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal.ingest([LocationSample]())

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func manualDayUnionsWithSamples() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal.ingest(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await services.reports.yearReport(for: 2026)
        let july4 = report.days.first { day in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
            let components = cal.dateComponents([.month, .day], from: day.date)
            return components.month == 7 && components.day == 4
        }
        #expect(july4?.regions == [.california, .newYork])
    }

    @Test func manualDayReplacesOnSecondCall() async throws {
        let (services, _, _) = try Self.makeServices()
        let date = WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00")
        try await services.journal.addManualDay(date: date, regions: [.california])
        try await services.journal.addManualDay(date: date, regions: [.newYork])

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.count == 1)
        // Second call should replace, not union, when there are no
        // GPS samples on the day — proves the store-level upsert on
        // `setManualDay` (not a delete-then-insert that would let
        // duplicates accumulate).
        #expect(report.days.first?.regions == [.newYork])
    }

    @Test func overrideDayReplacesGPSAttribution() async throws {
        let (services, _, _) = try Self.makeServices()
        // A stray GPS sample lands the day in California.
        try await services.journal.ingest(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        ))
        // The user corrects it to New York.
        try await services.journal.overrideDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.days.first?.regions == [.newYork])
        #expect(report.totals == [.newYork: 1])
    }

    @Test func overrideDayKeepsRawSamplesForUndo() async throws {
        let (services, store, _) = try Self.makeServices()
        let stray = sample(at: "2026-07-04T10:00:00-07:00")
        try await services.journal.ingest(stray)
        try await services.journal.overrideDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        // The override is non-destructive: the GPS sample is still on disk, so
        // clearing the manual day would restore the original attribution.
        #expect(try await store.allSamples().map(\.id) == [stray.id])
    }

    @Test func clearManualDayRestoresGPSAttribution() async throws {
        let (services, _, _) = try Self.makeServices()
        // GPS puts the day in California.
        try await services.journal.ingest(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        ))
        // The user wrongly relabels it to New York, then resets to GPS.
        try await services.journal.overrideDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )
        try await services.journal
            .clearManualDay(date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"))

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.first?.regions == [.california])
        #expect(report.totals == [.california: 1])
    }

    @Test func clearManualDayIsANoOpWithoutAManualRecord() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal
            .clearManualDay(date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"))

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.isEmpty)
    }

    @Test func additiveBackfillPreservesAnAuthoritativeRelabel() async throws {
        let (services, _, _) = try Self.makeServices()
        // GPS lands July 4 in California *and* New York (a stray cross-country hit).
        try await services.journal.ingest(sample(at: "2026-07-04T10:00:00-07:00"))
        try await services.journal.ingest(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-07-04T20:00:00-04:00"),
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            horizontalAccuracy: 5,
            source: .gpsVisit,
        ))
        // The user corrects the day to California only, removing the wrong NY hit.
        try await services.journal.overrideDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.california],
        )
        // A later range backfill (Canada) sweeps over the same corrected day.
        try await services.journal.addManualDays(
            from: WhereCoreTestSupport.iso("2026-07-01T00:00:00-07:00"),
            through: WhereCoreTestSupport.iso("2026-07-07T00:00:00-07:00"),
            regions: [.canada],
        )

        let report = try await services.reports.yearReport(for: 2026)
        let july4 = report.days.first {
            Self.pacificCalendar.isDate(
                $0.date,
                inSameDayAs: WhereCoreTestSupport.iso("2026-07-04T12:00:00-07:00"),
            )
        }
        // The relabel survives: New York stays removed (GPS is not resurrected)
        // and the backfilled Canada unions onto the corrected California.
        #expect(july4?.regions == [.california, .canada])
    }

    @Test func addManualDaysBackfillsEveryDayInRange() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal.addManualDays(
            from: WhereCoreTestSupport.iso("2026-02-10T09:00:00-08:00"),
            through: WhereCoreTestSupport.iso("2026-02-14T20:00:00-08:00"),
            regions: [.newYork],
        )

        let report = try await services.reports.yearReport(for: 2026)
        // Feb 10–14 inclusive is five days, each attributed to New York.
        #expect(report.days.count == 5)
        #expect(report.totals == [.newYork: 5])
        #expect(report.days.allSatisfy { $0.regions == [.newYork] })
    }

    @Test func addManualDaysWithStartAfterEndWritesNothing() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal.addManualDays(
            from: WhereCoreTestSupport.iso("2026-02-14T00:00:00-08:00"),
            through: WhereCoreTestSupport.iso("2026-02-10T00:00:00-08:00"),
            regions: [.california],
        )

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func addManualDaysSameStartAndEndWritesOneDay() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal.addManualDays(
            from: WhereCoreTestSupport.iso("2026-02-10T06:00:00-08:00"),
            through: WhereCoreTestSupport.iso("2026-02-10T23:00:00-08:00"),
            regions: [.california],
        )

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.totals == [.california: 1])
    }

    @Test func clearYearWipesAndReportsEmpty() async throws {
        let (services, _, _) = try Self.makeServices()
        try await services.journal.ingest(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await services.journal.clearYear(2026)
        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func eraseAllDataWipesEveryYear() async throws {
        let (services, _, _) = try Self.makeServices()
        for year in [2024, 2025, 2026] {
            try await services.journal.ingest(LocationSample(
                timestamp: WhereCoreTestSupport.iso("\(year)-03-15T12:00:00-07:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .manual,
            ))
        }

        try await services.journal.eraseAllData()

        // Unlike clearYear, the wipe spans every year, not just the selected one.
        for year in [2024, 2025, 2026] {
            let report = try await services.reports.yearReport(for: year)
            #expect(report.days.isEmpty)
            #expect(report.totals.isEmpty)
        }
    }

    @Test func resetStopsTrackingAndWipesTheStore() async throws {
        let (services, _, source) = try Self.makeServices()
        await services.ingestor.start()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { try await services.reports.yearReport(for: 2026).days.count == 1 }
        #expect(await services.ingestor.isActive)

        try await services.reset()

        // reset() owns the full teardown: GPS stopped and every year wiped.
        #expect(await !(services.ingestor.isActive))
        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func gpsFailuresEnqueueAndDrainOnRecovery() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource()
        let services = WhereServices(
            store: store,
            locationSource: source,
            aggregator: Self.makeAggregator(),
        )
        await services.ingestor.start()

        let sampleA = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        let sampleB = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:05:00-07:00"),
            coordinate: Coordinate(latitude: 37.7750, longitude: -122.4195),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        await store.setShouldFail(true)
        source.emit(sampleA)
        source.emit(sampleB)
        try await waitUntil { await services.ingestor.retryQueueDepth == 2 }
        #expect(await store.persistedCount == 0)

        await store.setShouldFail(false)
        let sampleC = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:10:00-07:00"),
            coordinate: Coordinate(latitude: 37.7751, longitude: -122.4196),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        source.emit(sampleC)
        // Wait on the true end-state (all three on disk). `retryQueueDepth`
        // briefly hits 0 mid-drain — the queue is cleared before sampleC is
        // persisted — so waiting on it instead races the final write.
        try await waitUntil { await store.persistedCount == 3 }
        #expect(await services.ingestor.retryQueueDepth == 0)

        await services.ingestor.stop()
    }

    @Test func trackingResumesAfterPauseWithoutDroppingSamples() async throws {
        let (services, _, source) = try Self.makeServices()

        await services.ingestor.start()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { try await services.reports.yearReport(for: 2026).days.count == 1 }

        // Pause, then resume. A naive implementation cancels the stream
        // consumer here, leaving the resumed session iterating a finished
        // stream so this second sample would be silently dropped.
        await services.ingestor.stop()
        let pausedActive = await services.ingestor.isActive
        #expect(!pausedActive)
        await services.ingestor.start()
        let resumedActive = await services.ingestor.isActive
        #expect(resumedActive)

        source.emit(sample(at: "2026-03-16T12:00:00-07:00"))
        try await waitUntil { try await services.reports.yearReport(for: 2026).days.count == 2 }

        await services.ingestor.stop()
    }

    /// Live GPS ingestion never goes through a session intent method, so the
    /// committed persist's `changes()` ping is the only thing that keeps readers
    /// fresh. Proves the live path funnels through the same unified signal a
    /// manual edit does.
    @Test func liveGPSIngestPingsDataChangeUpdates() async throws {
        let (services, _, source) = try Self.makeServices()
        // Subscribe before the ingest; the broadcaster buffers the newest ping,
        // so a commit landing before the consumer iterates still delivers.
        let changes = services.dataChangeUpdates()
        let recorder = PingRecorder()
        // Don't `break` after the first ping: keep draining so a duplicate
        // signal from the same commit would bump the count and fail the
        // exact-count assertion below.
        let consumer = Task { for await _ in changes {
            await recorder.record()
        } }

        await services.ingestor.start()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))

        try await waitUntil { await recorder.pingCount >= 1 }

        consumer.cancel()
        await services.ingestor.stop()

        // One ingested sample commits exactly one transaction, so the unified
        // signal must fire exactly once — a higher count would mean a single
        // write fanned out duplicate pings.
        #expect(await recorder.pingCount == 1)
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
            timestamp: WhereCoreTestSupport.iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }

    @Test func evidenceRoundTripsViaJournal() async throws {
        let (services, _, _) = try Self.makeServices()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: WhereCoreTestSupport.iso("2026-04-10T08:00:00-07:00"),
            region: .california,
            note: "SFO → JFK",
            contentType: .plainText,
        )
        let blob = Data("ticket pdf".utf8)
        try await services.journal.addEvidence(evidence, blob: blob)

        let fetched = try await services.journal.evidence(for: 2026)
        #expect(fetched == [evidence])

        let fetchedBlob = try await services.journal.evidenceBlob(for: evidence.id)
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

    /// Seed a journal's store with one sample, one evidence (with a blob),
    /// and one manual day so backup tests have all three tables populated.
    private func seedBackupData(_ services: WhereServices) async throws {
        try await services.journal.ingest(sample(at: "2026-03-15T12:00:00-07:00"))
        try await services.journal.addEvidence(Self.backupEvidence, blob: Self.backupBlob)
        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )
    }

    @Test func backupExportThenMergeImportReproducesEveryTable() async throws {
        let (source, sourceStore, _) = try Self.makeServices()
        try await seedBackupData(source)

        let url = try await source.backup.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeServices()
        let summary = try await destination.backup.importBackup(from: url, strategy: .merge)

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
        let (source, _, _) = try Self.makeServices()
        try await seedBackupData(source)
        let url = try await source.backup.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeServices()
        // A row that exists only on the destination and is absent from the
        // backup; merge must leave it in place.
        let preexisting = sample(at: "2026-01-01T09:00:00-08:00")
        try await destination.journal.addManualSample(preexisting)

        _ = try await destination.backup.importBackup(from: url, strategy: .merge)

        let ids = try await destinationStore.allSamples().map(\.id)
        #expect(ids.contains(preexisting.id))
        #expect(ids.count == 2)
    }

    @Test func backupReplaceImportWipesPreexistingRows() async throws {
        let (source, sourceStore, _) = try Self.makeServices()
        try await seedBackupData(source)
        let url = try await source.backup.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeServices()
        // Pre-existing destination data that the backup does not contain.
        try await destination.journal.addManualSample(sample(at: "2026-01-01T09:00:00-08:00"))
        try await destination.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-02-02T10:00:00-08:00"),
            regions: [.canada],
        )

        _ = try await destination.backup.importBackup(from: url, strategy: .replace)

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
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, _) = try Self.makeReminderServices(now: now, scheduler: spy)

        await services.reminders.configure(enabled: true, time: .defaultEvening)

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
        let (services, _, _) = try Self.makeReminderServices(
            now: WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00"),
            scheduler: spy,
        )

        await services.reminders.configure(enabled: false, time: .defaultEvening)

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
        #expect(await spy.lastBadgeCount == 0)
        #expect(await spy.lastScheduleDays.isEmpty)
    }

    @Test func loggingTodayViaGPSCancelsItsScheduledReminder() async throws {
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, source) = try Self.makeReminderServices(now: now, scheduler: spy)
        await services.reminders.configure(enabled: true, time: .defaultEvening)

        let today = Self.pacificCalendar.startOfDay(for: now)
        // Today is a forward nudge, not part of the backlog (Jan 1–4 = 4 days).
        #expect(await spy.lastBadgeCount == 4)
        #expect(await spy.lastScheduleDays.contains(today))

        await services.ingestor.start()
        source.emit(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-01-05T12:00:00-08:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))

        // Logging today removes today's reminder; the past backlog is unchanged.
        try await waitUntil { await !spy.lastScheduleDays.contains(today) }
        #expect(await spy.lastBadgeCount == 4)

        await services.ingestor.stop()
    }

    @Test func loggingPastDayViaGPSAfterTodayIsCoveredStillReconciles() async throws {
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, source) = try Self.makeReminderServices(now: now, scheduler: spy)
        await services.reminders.configure(enabled: true, time: .defaultEvening)

        await services.ingestor.start()
        source.emit(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-01-05T12:00:00-08:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))
        try await waitUntil { await spy.lastBadgeCount == 4 }

        // Visits can arrive late with their original timestamp. Even after the
        // reconciler knows today is covered, filling a past gap must lower the
        // backlog badge.
        source.emit(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-01-03T12:00:00-08:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        ))

        try await waitUntil { await spy.lastBadgeCount == 3 }

        await services.ingestor.stop()
    }

    @Test func manualDayLoggingAPastDayLowersTheBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-10T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, _) = try Self.makeReminderServices(now: now, scheduler: spy)
        await services.reminders.configure(enabled: true, time: .defaultEvening)

        // Backlog is Jan 1 – Mar 9 (today, Mar 10, is excluded): 68 days of 2026.
        #expect(await spy.lastBadgeCount == 68)

        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-03-03T12:00:00-08:00"),
            regions: [.california],
        )

        #expect(await spy.lastBadgeCount == 67)
    }

    @Test func clearCurrentYearReconcilesTheBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, _) = try Self.makeReminderServices(now: now, scheduler: spy)
        await services.reminders.configure(enabled: true, time: .defaultEvening)

        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-01-01T12:00:00-08:00"),
            regions: [.california],
        )
        // Backlog (Jan 1–4) minus the logged Jan 1 leaves 3.
        #expect(await spy.lastBadgeCount == 3)

        try await services.journal.clearYear(2026)

        // Clearing puts all four past days back into the backlog.
        #expect(await spy.lastBadgeCount == 4)
    }

    @Test func eraseAllDataReconcilesTheBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, _) = try Self.makeReminderServices(now: now, scheduler: spy)
        await services.reminders.configure(enabled: true, time: .defaultEvening)

        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-01-01T12:00:00-08:00"),
            regions: [.california],
        )
        // Backlog (Jan 1–4) minus the logged Jan 1 leaves 3.
        #expect(await spy.lastBadgeCount == 3)

        try await services.journal.eraseAllData()

        // Erasing everything puts all four past days back into the backlog,
        // proving the wipe reconciles the badge rather than leaving it stale.
        #expect(await spy.lastBadgeCount == 4)
    }

    @Test func changingReminderTimeReconcilesWithTheNewTime() async throws {
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, _) = try Self.makeReminderServices(now: now, scheduler: spy)

        await services.reminders.configure(enabled: true, time: .defaultEvening)
        await services.reminders.configure(enabled: true, time: ReminderTime(hour: 7, minute: 30))

        #expect(await spy.authorizationRequests == 2)
        #expect(await spy.reconcileCount == 2)
        #expect(await spy.lastReminderTime == ReminderTime(hour: 7, minute: 30))
        #expect(await spy.lastBadgeCount == 4)
    }

    @Test func disablingRemindersAfterEnablingClearsEverything() async throws {
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")
        let spy = SpyReminderScheduler()
        let (services, _, _) = try Self.makeReminderServices(now: now, scheduler: spy)

        await services.reminders.configure(enabled: true, time: .defaultEvening)
        #expect(await spy.lastBadgeCount == 4)

        await services.reminders.configure(enabled: false, time: .defaultEvening)
        #expect(await spy.lastEnabled == false)
        #expect(await spy.lastBadgeCount == 0)
        #expect(await spy.lastScheduleDays.isEmpty)
    }

    // MARK: - Daily summary

    @Test func configureDailySummaryEnabledBuildsRankedBody() async throws {
        let spy = SpyDailySummaryScheduler()
        let (services, _, _) = try Self.makeSummaryServices(
            now: WhereCoreTestSupport.iso("2026-01-10T09:00:00-08:00"),
            scheduler: spy,
        )
        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-01-01T12:00:00-08:00"),
            regions: [.california],
        )
        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-01-02T12:00:00-08:00"),
            regions: [.california],
        )
        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-01-03T12:00:00-08:00"),
            regions: [.california],
        )
        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-01-04T12:00:00-08:00"),
            regions: [.newYork],
        )

        await services.summary.configure(enabled: true, time: .defaultMorning)

        #expect(await spy.authorizationRequests == 1)
        #expect(await spy.lastEnabled == true)
        #expect(await spy.lastTime == .defaultMorning)
        // Ranked by day count desc; the single New York day stays singular.
        #expect(await spy.lastBody == "3 days in California, 1 day in New York")
    }

    @Test func configureDailySummaryWithNoDataUsesEmptyBody() async throws {
        let spy = SpyDailySummaryScheduler()
        let (services, _, _) = try Self.makeSummaryServices(
            now: WhereCoreTestSupport.iso("2026-01-10T09:00:00-08:00"),
            scheduler: spy,
        )

        await services.summary.configure(enabled: true, time: .defaultMorning)

        #expect(await spy.lastEnabled == true)
        #expect(await spy.lastBody == "No days logged yet this year.")
    }

    @Test func configureDailySummaryDisabledSkipsAuthAndSendsDisabled() async throws {
        let spy = SpyDailySummaryScheduler()
        let (services, _, _) = try Self.makeSummaryServices(
            now: WhereCoreTestSupport.iso("2026-01-10T09:00:00-08:00"),
            scheduler: spy,
        )

        await services.summary.configure(enabled: false, time: .defaultMorning)

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
    }

    // MARK: - Widget snapshot publishing

    private static func makeWidgetServices(
        refresher: SpyWidgetRefresher,
        store: (any WhereStore)? = nil,
        now: Date = Date(),
    ) throws -> (WhereServices, ScriptedLocationSource) {
        let source = ScriptedLocationSource()
        let services = try WhereServices(
            store: store ?? SwiftDataStore.inMemory(),
            locationSource: source,
            aggregator: makeAggregator(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: refresher,
            now: { now },
        )
        return (services, source)
    }

    @Test func committedWritesPublishWidgetSnapshots() async throws {
        let refresher = SpyWidgetRefresher()
        // Pin "now" to the day we log so the snapshot's `dayRegions` reflects it.
        let (services, _) = try Self.makeWidgetServices(
            refresher: refresher,
            now: WhereCoreTestSupport.iso("2026-03-15T20:00:00-07:00"),
        )

        try await services.journal.ingest(sample(at: "2026-03-15T12:00:00-07:00"))
        #expect(await refresher.publishCount == 1)
        // The published snapshot reflects the committed write: SF lands in CA,
        // both for today and in the year totals.
        let first = await refresher.lastSnapshot
        #expect(first?.dayRegions == [.california])
        #expect(first?.totals == [.california: 1])

        let day = WhereCoreTestSupport.iso("2026-07-04T15:00:00-07:00")
        try await services.journal.addManualDay(date: day, regions: [.newYork])
        try await services.journal.overrideDay(date: day, regions: [.california])
        try await services.journal.clearManualDay(date: day)
        try await services.journal.clearYear(2026)
        #expect(await refresher.publishCount == 5)
        // After clearing the year, the latest snapshot is empty again.
        #expect(await refresher.lastSnapshot?.totals.isEmpty == true)
    }

    @Test func refreshWidgetSnapshotPublishesFromExistingStoreWithoutAMutation() async throws {
        let store = try SwiftDataStore.inMemory()
        // Seed data straight into the store, bypassing the journal so
        // nothing is published — mirrors data that was synced/persisted in a
        // previous session and is sitting on disk at launch.
        let seed = sample(at: "2026-03-15T12:00:00-07:00")
        try await store.perform { try await store.add(sample: seed) }

        let refresher = SpyWidgetRefresher()
        let (services, _) = try Self.makeWidgetServices(
            refresher: refresher,
            store: store,
            now: WhereCoreTestSupport.iso("2026-03-15T20:00:00-07:00"),
        )

        // Freshly constructed services haven't published anything yet, so
        // the widget would be blank without an explicit refresh.
        #expect(await refresher.publishCount == 0)

        await services.widgets.refreshIfStale()

        #expect(await refresher.publishCount == 1)
        let snapshot = await refresher.lastSnapshot
        #expect(snapshot?.dayRegions == [.california])
        #expect(snapshot?.totals == [.california: 1])
    }

    @Test func gpsIngestPublishesWidgetSnapshot() async throws {
        let refresher = SpyWidgetRefresher()
        let (services, source) = try Self.makeWidgetServices(refresher: refresher)

        await services.ingestor.start()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await refresher.publishCount == 1 }

        await services.ingestor.stop()
    }

    @Test func failedGPSPersistSkipsWidgetPublishUntilRetrySucceeds() async throws {
        let refresher = SpyWidgetRefresher()
        let store = try ToggleFailingStore(backing: SwiftDataStore.inMemory())
        let (services, source) = try Self.makeWidgetServices(
            refresher: refresher,
            store: store,
        )

        await services.ingestor.start()
        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await services.ingestor.retryQueueDepth == 1 }
        // Nothing was committed, so the widgets have nothing new to show.
        #expect(await refresher.publishCount == 0)

        // The next successful persist drains the backlog and republishes.
        await store.setShouldFail(false)
        source.emit(sample(at: "2026-03-15T12:10:00-07:00"))
        try await waitUntil { await refresher.publishCount == 1 }

        await services.ingestor.stop()
    }

    @Test func redundantGPSSamplesSkipRepublishingButNewRegionsStillPublish() async throws {
        let refresher = SpyWidgetRefresher()
        let (services, _) = try Self.makeWidgetServices(
            refresher: refresher,
            now: WhereCoreTestSupport.iso("2026-03-15T20:00:00-07:00"),
        )

        // First CA sample today publishes.
        try await services.journal.ingest(sample(at: "2026-03-15T09:00:00-07:00"))
        #expect(await refresher.publishCount == 1)

        // A second CA sample the same day can't change what the widget shows —
        // today already counts CA — so it's skipped (no rebuild, no reload).
        try await services.journal.ingest(sample(at: "2026-03-15T13:00:00-07:00"))
        #expect(await refresher.publishCount == 1)

        // A NY sample adds a region to today, which must reach the widget.
        try await services.journal.ingest(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T15:00:00-07:00"),
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))
        #expect(await refresher.publishCount == 2)
        #expect(await refresher.lastSnapshot?.dayRegions == [.california, .newYork])
    }

    @Test func refreshWidgetSnapshotThrottlesUntilStaleOrNewDay() async throws {
        let refresher = SpyWidgetRefresher()
        let clock = MutableClock(WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))
        let store = try SwiftDataStore.inMemory()
        let seed = sample(at: "2026-03-15T07:00:00-07:00")
        try await store.perform { try await store.add(sample: seed) }
        let source = ScriptedLocationSource()
        let services = WhereServices(
            store: store,
            locationSource: source,
            aggregator: Self.makeAggregator(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: refresher,
            now: { clock.now },
        )

        // Cold publisher: the first passive refresh always publishes.
        await services.widgets.refreshIfStale()
        #expect(await refresher.publishCount == 1)

        // Same day, < 3h later: throttled.
        clock.advance(by: 2 * 60 * 60)
        await services.widgets.refreshIfStale()
        #expect(await refresher.publishCount == 1)

        // Same day, now > 3h since the last publish: rebuilds.
        clock.advance(by: 2 * 60 * 60)
        await services.widgets.refreshIfStale()
        #expect(await refresher.publishCount == 2)

        // A new calendar day always rebuilds, even moments later.
        clock.advance(by: 24 * 60 * 60)
        await services.widgets.refreshIfStale()
        #expect(await refresher.publishCount == 3)
    }
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

/// Counts `dataChangeUpdates()` pings, so a test can assert (via `waitUntil`)
/// that a committed write fired the unified signal — and, by checking the exact
/// count, that it fired exactly once rather than fanning out duplicates.
private actor PingRecorder {
    private(set) var pingCount = 0
    func record() {
        pingCount += 1
    }
}

/// Records the calls the reminder reconciler makes to its scheduler so tests
/// can assert the badge count, scheduled days, and enabled state without
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

/// Records the calls the summary reconciler makes to its scheduler so tests
/// can assert the recap body and enabled state without touching
/// `UNUserNotificationCenter`.
private actor SpyDailySummaryScheduler: DailySummaryScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?
    private(set) var lastTime: ReminderTime?
    private(set) var lastBody: String?
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

    func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
        reconcileCount += 1
        lastEnabled = enabled
        lastTime = time
        lastBody = body
    }
}

/// Records the snapshots the widget publisher emits so tests can assert
/// widgets repaint with the right data after committed writes — and stay
/// untouched when a write fails.
private actor SpyWidgetRefresher: WidgetTimelineRefreshing {
    private(set) var publishedSnapshots: [WidgetSnapshot] = []

    var publishCount: Int {
        publishedSnapshots.count
    }

    var lastSnapshot: WidgetSnapshot? {
        publishedSnapshots.last
    }

    func publish(_ snapshot: WidgetSnapshot) async {
        publishedSnapshots.append(snapshot)
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

    nonisolated func changes() -> AsyncStream<Void> {
        backing.changes()
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

    func dismissedIssueKeys() async throws -> Set<String> {
        try await backing.dismissedIssueKeys()
    }

    func allDismissedIssues() async throws -> [DismissedIssue] {
        try await backing.allDismissedIssues()
    }

    func setIssueDismissed(_ dismissed: Bool, key: String) async throws {
        try await backing.setIssueDismissed(dismissed, key: key)
    }

    func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        try await backing.restoreDismissedIssue(issue)
    }
}
