import Foundation
import LogKit

/// Owns the daily "log before the day ends" reminder intent and the
/// reconciliation that keeps the scheduled reminders + badge in sync with the
/// current year's missing-day picture.
///
/// This is the single source of truth for "recorded successfully -> drop
/// today's reminder and lower the badge": every committed write that can change
/// the day picture calls `reconcile()` (or the cheaper `reconcileAfterIngest`
/// on the hot GPS path).
public actor ReminderReconciler {
    private let scheduler: any LoggingReminderScheduling
    private let reportReader: ReportReader
    /// Scanner shared with the Resolve tab, used to fold the unresolved
    /// data-issue count into the app-icon badge (so the badge means "things that
    /// need you", not just missing days).
    private let issueScanner: DataIssueScanner
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let windowDays: Int

    private var config = Configuration()

    /// The start-of-day we last reconciled while today already had presence.
    /// Lets the GPS ingest path skip a full re-scan once today is covered
    /// (significant-change events can fire many times a day).
    private var todayCoveredByReconcile: Date?

    private struct Configuration {
        var enabled = false
        var time: ReminderTime = .defaultEvening
        /// Whether the data-issue count contributes to the badge. Independent of
        /// `enabled`, so issues still badge the icon when logging reminders are off.
        var issueAlertsEnabled = false
        /// The GPS border-drift threshold the badge's issue scan runs at.
        var driftThresholdMeters = Double(DriftThreshold.default.rawValue)
    }

    /// How many days past today the per-day reminders are scheduled ahead, so a
    /// stretch where the app never runs still has reminders queued. Today plus
    /// this many days.
    static let defaultWindowDays = 6

    private static let logger = WhereLog.channel(.reminderReconciler)

    init(
        scheduler: any LoggingReminderScheduling,
        reportReader: ReportReader,
        issueScanner: DataIssueScanner,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        windowDays: Int = ReminderReconciler.defaultWindowDays,
    ) {
        self.scheduler = scheduler
        self.reportReader = reportReader
        self.issueScanner = issueScanner
        self.calendar = calendar
        self.now = now
        self.windowDays = windowDays
    }

    /// Set the user's reminder intent (enabled + time of day) plus the inputs the
    /// badge's data-issue contribution needs (whether issue alerts are on and the
    /// current drift threshold), request notification permission when enabling,
    /// then reconcile the scheduled reminders and badge. Safe to call on every
    /// launch and whenever the user changes a setting.
    public func configure(
        enabled: Bool,
        time: ReminderTime,
        issueAlertsEnabled: Bool,
        driftThresholdMeters: Double,
    ) async {
        config = Configuration(
            enabled: enabled,
            time: time,
            issueAlertsEnabled: issueAlertsEnabled,
            driftThresholdMeters: driftThresholdMeters,
        )
        if enabled {
            _ = await scheduler.requestAuthorization()
        }
        await reconcile()
    }

    /// Explicitly drive the notification permission prompt (e.g. from a
    /// Settings toggle). Returns whether the app is authorized afterward.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        await scheduler.requestAuthorization()
    }

    /// Whether the app is currently authorized to post reminders / set the
    /// badge, so the UI can surface an "open Settings" affordance.
    public func isAuthorized() async -> Bool {
        await scheduler.isAuthorized()
    }

    /// Cheap reconcile for the GPS ingest path: skips work once today is already
    /// known to be covered, so a burst of significant-change samples doesn't
    /// trigger a full-year scan each time. Runs when reminders are on *or* when
    /// issue alerts are on (the badge's issue count also needs to refresh after a
    /// background ingest). When reminders are off `todayCoveredByReconcile` stays
    /// nil, so the coverage shortcut simply doesn't apply.
    func reconcileAfterIngest(changedDays: Set<Date>) async {
        guard config.enabled || config.issueAlertsEnabled else { return }
        let today = calendar.startOfDay(for: now())
        let changedDayNeedsReconcile = changedDays.contains { $0 != today }
        guard todayCoveredByReconcile != today || changedDayNeedsReconcile else { return }
        await reconcile()
    }

    /// Recompute the current-year missing-day picture from the store and push
    /// it to the scheduler: the badge is the total unlogged days this year plus
    /// the unresolved data-issue count, and a rolling window of upcoming unlogged
    /// days gets per-day reminders.
    func reconcile() async {
        let today = calendar.startOfDay(for: now())
        let year = calendar.component(.year, from: today)

        guard config.enabled else {
            // Reminders off: no per-day reminders, but the badge still surfaces
            // the unresolved-issue count when issue alerts are on. (No report in
            // hand here, so the scan reads its own.)
            let issueBadge = await dataIssueBadgeCount(year: year, report: nil)
            await scheduler.reconcile(
                badgeCount: issueBadge,
                scheduleDays: [],
                reminderTime: config.time,
                enabled: false,
            )
            todayCoveredByReconcile = nil
            return
        }

        do {
            let report = try await reportReader.yearReport(for: year)
            let present = Set(report.days.map { calendar.startOfDay(for: $0.date) })
            // The badge backlog is *past* misses only — today is still loggable,
            // so it's covered by the forward-looking reminder below rather than
            // counted as missed (otherwise the app would warn every morning).
            let backlog = MissingDays.missingDayKeys(
                year: year,
                through: MissingDays.backlogCutoff(asOf: now(), calendar: calendar),
                present: present,
                calendar: calendar,
            )
            let windowEnd = calendar.date(
                byAdding: .day,
                value: windowDays,
                to: today,
            ) ?? today
            let scheduleDays = today
                .calendarDays(through: windowEnd, in: calendar)
                .filter { !present.contains($0) }
            // Reuse the report we already read to derive the ranking the issue
            // scan needs, avoiding a second store read on this hot path.
            let issueBadge = await dataIssueBadgeCount(year: year, report: report)
            await scheduler.reconcile(
                badgeCount: backlog.count + issueBadge,
                scheduleDays: scheduleDays,
                reminderTime: config.time,
                enabled: true,
            )
            todayCoveredByReconcile = present.contains(today) ? today : nil
        } catch {
            Self.logger.error(
                "Failed to reconcile logging reminders: \(error.localizedDescription)",
            )
        }
    }

    /// The unresolved data-issue count that folds into the badge, or 0 when issue
    /// alerts are off. Reuses `report` when the caller already has it (the hot
    /// reminder path) and otherwise lets the scanner read its own. Scan failures
    /// log and contribute 0 rather than blanking the whole badge.
    private func dataIssueBadgeCount(year: Int, report: YearReport?) async -> Int {
        guard config.issueAlertsEnabled else { return 0 }
        do {
            if let report {
                return try await issueScanner.issues(
                    year: year,
                    primaryRegions: Region.primaryRegions(in: report.totals),
                    driftThresholdMeters: config.driftThresholdMeters,
                ).count
            }
            return try await issueScanner.currentIssueCount(
                year: year,
                driftThresholdMeters: config.driftThresholdMeters,
            )
        } catch {
            Self.logger.warning(
                "Failed to scan data issues for badge: \(error.localizedDescription)",
            )
            return 0
        }
    }
}
