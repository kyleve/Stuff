import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers export/import round-trips and the post-import widget publish the
/// controller delegates to `BackupCoordinator`.
struct BackupCoordinatorTests {
    private struct Harness {
        let coordinator: BackupCoordinator
        let store: SwiftDataStore
        let widgets: SpyRefresher
        let reminders: ReminderReconciler
        let reminderScheduler: SpyReminderScheduler
        let issueAlertScheduler: SpyIssueAlertScheduler
    }

    private actor SpyRefresher: WidgetTimelineRefreshing {
        private(set) var publishCount = 0
        func publish(_: WidgetSnapshot) async {
            publishCount += 1
        }
    }

    /// Records the app-icon badge reconciles so a test can assert an import
    /// recomputes the badge off the imported data.
    private actor SpyReminderScheduler: LoggingReminderScheduling {
        private(set) var reconcileCount = 0
        private(set) var lastBadgeCount: Int?
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
            enabled _: Bool,
        ) async {
            reconcileCount += 1
            lastBadgeCount = badgeCount
        }
    }

    /// Records the issue-alert reconciles so a test can assert an import
    /// refreshes the "issues to resolve" notification.
    private actor SpyIssueAlertScheduler: DataIssueAlertScheduling {
        private(set) var reconcileCount = 0
        func requestAuthorization() async -> Bool {
            true
        }

        func isAuthorized() async -> Bool {
            true
        }

        func reconcile(enabled _: Bool, time _: ReminderTime, body _: String) async {
            reconcileCount += 1
        }
    }

    private static func makeHarness(
        now: Date = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00"),
    ) throws -> Harness {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
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
            calendar: aggregator.calendar,
            now: { now },
        )
        let reports = ReportReader(store: store, aggregator: aggregator, attributor: .shared)
        let scanner = DataIssueScanner(
            reportReader: reports,
            attributor: .shared,
            calendar: aggregator.calendar,
            now: { now },
            storeChanges: store.changes(),
        )
        let reminderScheduler = SpyReminderScheduler()
        let reminders = ReminderReconciler(
            scheduler: reminderScheduler,
            reportReader: reports,
            issueScanner: scanner,
            calendar: aggregator.calendar,
            now: { now },
        )
        let issueAlertScheduler = SpyIssueAlertScheduler()
        let issueAlerts = DataIssueAlertReconciler(
            scheduler: issueAlertScheduler,
            scanner: scanner,
            calendar: aggregator.calendar,
            now: { now },
        )
        let coordinator = BackupCoordinator(
            store: store,
            widgets: widgets,
            issueScanner: scanner,
            reminders: reminders,
            issueAlerts: issueAlerts,
        )
        return Harness(
            coordinator: coordinator,
            store: store,
            widgets: refresher,
            reminders: reminders,
            reminderScheduler: reminderScheduler,
            issueAlertScheduler: issueAlertScheduler,
        )
    }

    private static let evidence = Evidence(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .boardingPass,
        capturedAt: Date(timeIntervalSince1970: 1_700_050_000),
        region: .california,
        note: "SFO → JFK",
        contentType: .pdf,
    )
    private static let blob = Data("boarding-pass-pdf".utf8)

    private static let dismissal = DismissedIssue(
        key: "borderDrift:1700000000",
        dismissedAt: Date(timeIntervalSince1970: 1_700_000_000),
    )

    /// Seed all four tables (sample, evidence + blob, manual day, dismissed
    /// issue) directly into a store so backup tests don't depend on the journal.
    private static func seed(_ store: SwiftDataStore) async throws {
        try await store.perform {
            try await store.add(sample: sample(at: "2026-03-15T12:00:00-07:00"))
            try await store.write(evidence: evidence, blob: blob)
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-07-04T00:00:00-07:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
            try await store.restoreDismissedIssue(dismissal)
        }
    }

    @Test func exportThenMergeImportReproducesEveryTable() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)

        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let summary = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        #expect(summary.sampleCount == 1)
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)
        #expect(summary.dismissedIssueCount == 1)

        #expect(try await destination.store.allSamples() == source.store.allSamples())
        #expect(try await destination.store.allEvidence() == source.store.allEvidence())
        #expect(try await destination.store.allManualDays() == source.store.allManualDays())
        // Dismissals come back verbatim (key + original timestamp).
        #expect(try await destination.store.allDismissedIssues() == source.store
            .allDismissedIssues())
        #expect(try await destination.store.allDismissedIssues() == [Self.dismissal])
        #expect(try await destination.store.evidenceBlob(for: Self.evidence.id) == Self.blob)
        // An import that lands new data republishes the widget snapshot.
        #expect(await destination.widgets.publishCount == 1)
    }

    @Test func mergeImportKeepsPreexistingRows() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let preexisting = Self.sample(at: "2026-01-01T09:00:00-08:00")
        try await destination.store.perform { try await destination.store.add(sample: preexisting) }

        _ = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        let ids = try await destination.store.allSamples().map(\.id)
        #expect(ids.contains(preexisting.id))
        #expect(ids.count == 2)
    }

    @Test func replaceImportWipesPreexistingRows() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        try await destination.store.perform {
            try await destination.store.add(sample: Self.sample(at: "2026-01-01T09:00:00-08:00"))
            try await destination.store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-02T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.canada],
            ))
            // A preexisting dismissal that the file doesn't contain must be wiped
            // by `.replace` so the device mirrors the file exactly.
            try await destination.store.restoreDismissedIssue(DismissedIssue(
                key: "missingDays:42",
                dismissedAt: Date(timeIntervalSince1970: 1),
            ))
        }

        _ = try await destination.coordinator.importBackup(from: url, strategy: .replace)

        #expect(try await destination.store.allSamples() == source.store.allSamples())
        #expect(try await destination.store.allManualDays() == source.store.allManualDays())
        #expect(try await destination.store.allDismissedIssues() == source.store
            .allDismissedIssues())
        #expect(try await destination.store.allDismissedIssues() == [Self.dismissal])
    }

    /// Regression guard: an import rewrites day data, so it must reconcile the
    /// app-icon badge and the issues-to-resolve notification off the fresh data
    /// rather than leaving them at their pre-import values (the "home-screen
    /// badge stuck at 157 after replace import" bug). The headless reconcilers
    /// don't observe `store.changes()`, so the import has to drive them.
    @Test func replaceImportReconcilesTheBadgeOffTheImportedData() async throws {
        // Frozen at Jan 5, so the backlog window is just Jan 1–4.
        let now = WhereCoreTestSupport.iso("2026-01-05T09:00:00-08:00")

        // Source covers the whole backlog window, so it exports a fully-logged
        // start of year (no missing days, no unresolved issues).
        let source = try Self.makeHarness(now: now)
        try await source.store.perform {
            for iso in [
                "2026-01-01T12:00:00-08:00",
                "2026-01-02T12:00:00-08:00",
                "2026-01-03T12:00:00-08:00",
                "2026-01-04T12:00:00-08:00",
            ] {
                try await source.store.setManualDay(DayPresence(
                    date: WhereCoreTestSupport.iso(iso),
                    in: WhereCoreTestSupport.calendar(),
                    regions: [.california],
                ))
            }
        }
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Destination enables reminders + issue alerts while empty, so its badge
        // starts at the fully-missing-year count (Jan 1–4 backlog + one
        // missing-days range).
        let destination = try Self.makeHarness(now: now)
        await destination.reminders.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Double(DriftThreshold.default.rawValue),
        )
        let emptyBadge = await destination.reminderScheduler.lastBadgeCount
        let remindersBeforeImport = await destination.reminderScheduler.reconcileCount
        let issueAlertsBeforeImport = await destination.issueAlertScheduler.reconcileCount

        _ = try await destination.coordinator.importBackup(from: url, strategy: .replace)

        // Both headless reconcilers ran on the import.
        #expect(await destination.reminderScheduler.reconcileCount > remindersBeforeImport)
        #expect(await destination.issueAlertScheduler.reconcileCount > issueAlertsBeforeImport)
        // The badge was recomputed off the imported data — backlog + one missing
        // range while empty, dropping to zero once Jan 1–4 are all logged.
        #expect(emptyBadge == 5)
        #expect(await destination.reminderScheduler.lastBadgeCount == 0)
    }

    /// The coordinator owns the export staging directory's lifecycle: starting a
    /// new export purges the previous one, so at most one archive sits on disk.
    @Test func exportPurgesThePreviousExportDirectory() async throws {
        let harness = try Self.makeHarness()
        try await Self.seed(harness.store)

        let first = try await harness.coordinator.exportBackup()
        let firstDirectory = first.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: first.path))

        let second = try await harness.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }

        #expect(!FileManager.default.fileExists(atPath: firstDirectory.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func importReportsProgressUpToCompletion() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let recorder = ProgressRecorder()
        _ = try await destination.coordinator
            .importBackup(from: url, strategy: .replace) { fraction in
                recorder.record(fraction)
            }

        let fractions = recorder.fractions
        #expect(!fractions.isEmpty)
        #expect(fractions.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(fractions.last == 1)
    }

    private final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func record(_ value: Double) {
            lock.withLock { values.append(value) }
        }

        var fractions: [Double] {
            lock.withLock { values }
        }
    }

    private static func sample(at isoString: String) -> LocationSample {
        LocationSample(
            id: UUID(),
            timestamp: WhereCoreTestSupport.iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }
}
