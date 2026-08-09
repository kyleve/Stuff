import Foundation
import PeriscopeCore
import RegionKit

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
    private let currentDeviceID: RecordingDeviceID
    private let now: @Sendable () -> Date

    private static let logger = WhereLog.root(DayJournalLog.self)

    init(
        store: any WhereStore,
        aggregator: DayAggregator,
        reminders: ReminderReconciler,
        issueAlerts: DataIssueAlertReconciler,
        issueScanner: DataIssueScanner,
        widgets: WidgetSnapshotPublisher,
        currentDeviceID: RecordingDeviceID,
        now: @escaping @Sendable () -> Date,
    ) {
        self.store = store
        self.aggregator = aggregator
        self.reminders = reminders
        self.issueAlerts = issueAlerts
        self.issueScanner = issueScanner
        self.widgets = widgets
        self.currentDeviceID = currentDeviceID
        self.now = now
    }

    // MARK: - Post-write reconciliation

    /// Recount data issues and reconcile the reminder badge + the "issues to
    /// resolve" notification off the fresh count. The subset every committed
    /// write shares; a write that changes *day data* additionally republishes
    /// the widget snapshot via `reconcileAfterDayDataChange()`.
    ///
    /// The scanner is invalidated inline (not just via its async store-change
    /// observation) so the reconciles below recount from fresh data rather than
    /// racing it.
    private func reconcileIssueState() async {
        await Self.logger.measure(.reconcileIssueState, budget: .seconds(3)) {
            await issueScanner.invalidate()
            await reminders.reconcile()
            await issueAlerts.reconcile()
        }
    }

    /// Full reconcile after a change to persisted day data (manual overlays,
    /// clears): recount issues / badge / notification, then republish the widget
    /// snapshot. Every local day-mutating write funnels through here; backup and
    /// remote imports use the composition root's full derived-data fan-out.
    func reconcileAfterDayDataChange() async {
        await Self.logger.measure(.reconcileAfterDayDataChange, budget: .seconds(5)) {
            await reconcileIssueState()
            await widgets.publish()
        }
    }

    /// Reminder/issue fan-out plus the hot-path widget policy: skip a rebuild
    /// when the sample cannot change what widgets show (same day + region).
    private func reconcileAfterSampleIngest(_ sample: LocationSample) async {
        await reconcileIssueState()
        await widgets.publishAfterIngest(of: sample)
    }

    // MARK: - Ingestion

    public func ingest(_ sample: LocationSample) async throws {
        try await store.performInCurrentGeneration {
            try await store.add(sample: sample)
        }
        await reconcileAfterSampleIngest(sample)
    }

    /// Persist many samples in a *single* transaction, rebuilding the widget
    /// snapshot once at the end instead of once per sample. The single-sample
    /// `ingest(_:)` is the right call for live GPS (events arrive minutes
    /// apart), but bulk loads — test fixtures, future bulk imports — would
    /// otherwise open one transaction *and* re-aggregate the whole year per
    /// sample, which is quadratic in the batch size. An empty batch is a no-op.
    public func ingest(_ samples: [LocationSample]) async throws {
        guard !samples.isEmpty else { return }
        try await Self.logger.measure(.ingestBatch, budget: .seconds(5)) {
            try await store.performInCurrentGeneration {
                for sample in samples {
                    try await store.add(sample: sample)
                }
            }
        }
        await reconcileAfterDayDataChange()
    }

    /// Persist an approved photo-history draft as one transaction, including
    /// any authoritative day corrections made in the preview. Re-importing is
    /// idempotent because the planner gives every sample a deterministic id.
    public func importPhotoHistory(_ history: PhotoHistoryImport) async throws {
        guard !history.samples.isEmpty || !history.corrections.isEmpty else { return }
        try await Self.logger.measure(.importPhotoHistory, budget: .seconds(5)) {
            try await store.performInCurrentGeneration {
                for sample in history.samples {
                    try await store.add(sample: sample)
                }
                for correction in history.corrections {
                    try await store.setManualDay(correction)
                }
            }
        }
        await reconcileAfterDayDataChange()
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await store.performInCurrentGeneration {
            try await store.add(sample: sample)
        }
        await reconcileAfterSampleIngest(sample)
    }

    public func addManualDay(
        date: Date,
        regions: Set<Region>,
        audit: ManualEntryAudit?,
    ) async throws {
        let day = CalendarDay(from: date, in: aggregator.calendar)
        let presence = DayPresence(day: day, regions: regions, audit: audit)
        try await store.performInCurrentGeneration {
            try await store.setManualDay(presence)
        }
        await reconcileAfterDayDataChange()
        Self.logger { .addedManualDay(day: String(describing: day), regionCount: regions.count) }
    }

    /// Authoritatively set the regions for a single calendar day, *replacing*
    /// whatever GPS (or a prior manual overlay) attributed to it. Unlike
    /// `addManualDay`, this does not union with GPS — it's the "correct a wrong
    /// attribution" path. The raw GPS samples are left untouched, so the fix is
    /// non-destructive and undone by `clearManualDay(date:)`.
    public func overrideDay(
        date: Date,
        regions: Set<Region>,
        audit: ManualEntryAudit?,
    ) async throws {
        let day = CalendarDay(from: date, in: aggregator.calendar)
        let presence = DayPresence(day: day, regions: regions, isAuthoritative: true, audit: audit)
        try await store.performInCurrentGeneration {
            try await store.setManualDay(presence)
        }
        await reconcileAfterDayDataChange()
        Self.logger { .overrodeDay(day: String(describing: day), regionCount: regions.count) }
    }

    /// Drop the manual overlay for a single calendar day, restoring the
    /// GPS-derived attribution (the relabel "reset to GPS" path). A no-op when
    /// the day has no manual record. Raw samples are never touched, so this
    /// simply lets the aggregator fall back to whatever GPS recorded.
    public func clearManualDay(date: Date) async throws {
        let day = CalendarDay(from: date, in: aggregator.calendar)
        try await store.performInCurrentGeneration {
            try await store.clearManualDay(day)
        }
        await reconcileAfterDayDataChange()
        Self.logger { .clearedManualDay(day: String(describing: day)) }
    }

    /// Drop the manual overlays for several calendar days (the logged-days
    /// list's swipe / multi-delete), restoring each day's GPS-derived
    /// attribution. All deletes run inside a *single* `store.perform`
    /// transaction, so it's **all-or-nothing**: a failure part-way through rolls
    /// the whole batch back rather than leaving half the days cleared (see
    /// `WhereStore.perform`). Keys are normalized to start-of-day; a day with no
    /// manual record is silently skipped by the store. An empty input is a no-op
    /// (no transaction, no reconcile). Batching also keeps the reconcile + widget
    /// publish to once for the whole delete rather than once per day.
    public func clearManualDays(dates: [Date]) async throws {
        guard !dates.isEmpty else { return }
        let days = dates.map { CalendarDay(from: $0, in: aggregator.calendar) }
        try await Self.logger.measure(.clearManualDays, budget: .seconds(2)) {
            try await store.performInCurrentGeneration {
                for day in days {
                    try await store.clearManualDay(day)
                }
            }
        }
        await reconcileAfterDayDataChange()
        Self.logger { .clearedManualDays(dayCount: days.count) }
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
        audit: ManualEntryAudit?,
    ) async throws {
        // `days(through:)` returns an immutable array, so the `@Sendable`
        // transaction body captures a `let` rather than a mutable cursor across
        // the concurrency boundary.
        let calendar = aggregator.calendar
        let days = CalendarDay(from: start, in: calendar)
            .days(through: CalendarDay(from: end, in: calendar))
        guard !days.isEmpty else { return }
        // One audit stamps every day in the range — it records the single act of
        // entry, not a per-day fact.
        try await Self.logger.measure(.backfillDays, budget: .seconds(2)) {
            try await store.performInCurrentGeneration {
                for day in days {
                    try await store.setManualDay(
                        DayPresence(day: day, regions: regions, audit: audit),
                    )
                }
            }
        }
        await reconcileAfterDayDataChange()
        Self.logger {
            .backfilledManualDays(dayCount: days.count, regionCount: regions.count)
        }
    }

    // MARK: - Clearing

    public func clearYear(_ year: Int) async throws {
        let interval = aggregator.yearInterval(year: year)
        let dayRange = CalendarDay.yearRange(year)
        try await Self.logger.measure(.clearYear, budget: .seconds(5)) {
            try await store.performInCurrentGeneration {
                try await store.clear(in: interval, manualDays: dayRange)
            }
        }
        await reconcileAfterDayDataChange()
        Self.logger { .clearedYear(year: year) }
    }

    /// Erase every sample, manual day, and piece of evidence in the store, then
    /// reconcile the reminder schedule/badge and republish an (now empty) widget
    /// snapshot. The store half of the app's reset/erase teardown. Mirrors
    /// `clearYear`'s reconciliation so the badge/reminders reflect the now-empty
    /// store immediately rather than relying on a later launch step.
    public func eraseAllData() async throws {
        let resetAt = now()
        try await Self.logger.measure(.eraseAllData, budget: .seconds(10)) {
            try await store.perform {
                let deviceIDs = try await Set(store.recordingDeviceProfiles().map(\.id))
                    .union([currentDeviceID])
                _ = try await store.rotateDataGeneration(
                    reason: .accountReset,
                    changedBy: currentDeviceID,
                    at: resetAt,
                )
                for deviceID in deviceIDs {
                    try await store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                        id: .init(rawValue: UUID()),
                        deviceID: deviceID,
                        removedAt: resetAt,
                        removedByDeviceID: currentDeviceID,
                    ))
                }
            }
        }
        await reconcileAfterDayDataChange()
        Self.logger { .erasedAllData }
    }

    // MARK: - Evidence

    public func addEvidence(_ evidence: Evidence, blob: Data? = nil) async throws {
        try await store.performInCurrentGeneration {
            try await store.write(evidence: evidence, blob: blob)
        }
        Self.logger {
            .wroteEvidence(id: String(describing: evidence.id), hasBlob: blob != nil)
        }
    }

    public func evidence(for year: Int) async throws -> [Evidence] {
        try await store.evidence(in: aggregator.yearInterval(year: year))
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        try await store.evidenceBlob(for: id)
    }

    // MARK: - Data resolution dismissals

    public func dismissIssue(id: DataIssueID) async throws {
        try await store.performInCurrentGeneration {
            try await store.setIssueDismissed(true, id: id)
        }
        // Dismissing removes the issue from the unresolved count, so the badge
        // and the "issues to resolve" notification both have to recount. No
        // widget publish: a dismissal doesn't change day data.
        await reconcileIssueState()
    }

    public func restoreIssue(id: DataIssueID) async throws {
        try await store.performInCurrentGeneration {
            try await store.setIssueDismissed(false, id: id)
        }
        await reconcileIssueState()
    }
}
