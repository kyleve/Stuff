import Foundation
import LogKit

/// Owns the user-sourced writes into the store — sample ingestion, manual-day
/// overlays, range backfills, year/all clears, evidence, and data-resolution
/// dismissals — together with the reminder reconcile + widget publish each
/// day mutation triggers.
///
/// Every write runs inside a single `store.perform` transaction and then
/// *awaits* its reminder reconcile / widget publish in sequence, so the existing
/// "a write fully commits before a reconcile/publish reads it" property holds.
public actor DayJournal {
    private let store: any WhereStore
    private let aggregator: DayAggregator
    private let reminders: ReminderReconciler
    private let issueAlerts: DataIssueAlertReconciler
    /// Shared scanner behind the badge/notification issue count. Dropped inline
    /// after each committed write so the reconciles below recount from fresh
    /// data rather than racing the scanner's async store-change invalidation.
    private let issueScanner: DataIssueScanner
    private let widgets: WidgetSnapshotPublisher

    private static let logger = WhereLog.channel(.dayJournal)

    init(
        store: any WhereStore,
        aggregator: DayAggregator,
        reminders: ReminderReconciler,
        issueAlerts: DataIssueAlertReconciler,
        issueScanner: DataIssueScanner,
        widgets: WidgetSnapshotPublisher,
    ) {
        self.store = store
        self.aggregator = aggregator
        self.reminders = reminders
        self.issueAlerts = issueAlerts
        self.issueScanner = issueScanner
        self.widgets = widgets
    }

    // MARK: - Ingestion

    public func ingest(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
        await widgets.publishAfterIngest(of: sample)
    }

    /// Persist many samples in a *single* transaction, rebuilding the widget
    /// snapshot once at the end instead of once per sample. The single-sample
    /// `ingest(_:)` is the right call for live GPS (events arrive minutes
    /// apart), but bulk loads — test fixtures, future bulk imports — would
    /// otherwise open one transaction *and* re-aggregate the whole year per
    /// sample, which is quadratic in the batch size. An empty batch is a no-op.
    public func ingest(_ samples: [LocationSample]) async throws {
        guard !samples.isEmpty else { return }
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        await widgets.publish()
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
        await widgets.publish()
    }

    public func addManualDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        let presence = DayPresence(date: key, regions: regions)
        try await store.perform { try await store.setManualDay(presence) }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
        await widgets.publish()
        Self.logger.info(
            "Added manual day \(Self.dayLogLabel(key, calendar: aggregator.calendar)) with \(regions.count) region(s)",
        )
    }

    /// Authoritatively set the regions for a single calendar day, *replacing*
    /// whatever GPS (or a prior manual overlay) attributed to it. Unlike
    /// `addManualDay`, this does not union with GPS — it's the "correct a wrong
    /// attribution" path. The raw GPS samples are left untouched, so the fix is
    /// non-destructive and undone by `clearManualDay(date:)`.
    public func overrideDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        let presence = DayPresence(date: key, regions: regions, isAuthoritative: true)
        try await store.perform { try await store.setManualDay(presence) }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
        await widgets.publish()
        Self.logger.info(
            "Overrode day \(Self.dayLogLabel(key, calendar: aggregator.calendar)) with \(regions.count) region(s)",
        )
    }

    /// Drop the manual overlay for a single calendar day, restoring the
    /// GPS-derived attribution (the relabel "reset to GPS" path). A no-op when
    /// the day has no manual record. Raw samples are never touched, so this
    /// simply lets the aggregator fall back to whatever GPS recorded.
    public func clearManualDay(date: Date) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        try await store.perform { try await store.clearManualDay(key) }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
        await widgets.publish()
        Self.logger.info(
            "Cleared manual overlay for day \(Self.dayLogLabel(key, calendar: aggregator.calendar))",
        )
    }

    /// Assert `regions` for every calendar day in the inclusive range
    /// `start...end` (handy for backfilling a trip). Both bounds are normalized
    /// to start-of-day in the aggregator's calendar, and the whole range is
    /// written inside a single `perform` transaction so the backfill commits
    /// (or rolls back) atomically. A `start` later than `end` is treated as an
    /// empty range and writes nothing.
    public func addManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
    ) async throws {
        // `calendarDays` returns an immutable array, so the `@Sendable`
        // transaction body captures a `let` rather than a mutable cursor across
        // the concurrency boundary.
        let dayKeys = start.calendarDays(through: end, in: aggregator.calendar)
        guard !dayKeys.isEmpty else { return }
        try await store.perform {
            for day in dayKeys {
                try await store.setManualDay(DayPresence(date: day, regions: regions))
            }
        }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
        await widgets.publish()
        Self.logger.info(
            "Backfilled \(dayKeys.count) manual day(s) with \(regions.count) region(s)",
        )
    }

    // MARK: - Clearing

    public func clearYear(_ year: Int) async throws {
        let interval = aggregator.yearInterval(year: year)
        try await store.perform { try await store.clear(in: interval) }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
        await widgets.publish()
        Self.logger.info("Cleared year \(year)")
    }

    /// Erase every sample, manual day, and piece of evidence in the store, then
    /// reconcile the reminder schedule/badge and republish an (now empty) widget
    /// snapshot. The store half of the app's reset/erase teardown. Mirrors
    /// `clearYear`'s reconciliation so the badge/reminders reflect the now-empty
    /// store immediately rather than relying on a later launch step.
    public func eraseAllData() async throws {
        try await store.perform { try await store.clearAll() }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
        await widgets.publish()
        Self.logger.info("Erased all store data")
    }

    // MARK: - Evidence

    public func addEvidence(_ evidence: Evidence, blob: Data? = nil) async throws {
        try await store.perform { try await store.write(evidence: evidence, blob: blob) }
        Self.logger.info("Wrote evidence \(evidence.id) (blob: \(blob != nil))")
    }

    public func evidence(for year: Int) async throws -> [Evidence] {
        try await store.evidence(in: aggregator.yearInterval(year: year))
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        try await store.evidenceBlob(for: id)
    }

    // MARK: - Data resolution dismissals

    public func dismissIssue(key: String) async throws {
        try await store.perform { try await store.setIssueDismissed(true, key: key) }
        // Dismissing removes the issue from the unresolved count, so the badge
        // and the "issues to resolve" notification both have to recount.
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
    }

    public func restoreIssue(key: String) async throws {
        try await store.perform { try await store.setIssueDismissed(false, key: key) }
        await issueScanner.invalidate()
        await reminders.reconcile()
        await issueAlerts.reconcile()
    }

    private static func dayLogLabel(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
        )
    }
}
