import Foundation
import os

/// Owns the daily "log before the day ends" reminder intent and the
/// reconciliation that keeps the scheduled reminders + badge in sync with the
/// current year's missing-day picture.
///
/// This is the single source of truth for "recorded successfully -> drop
/// today's reminder and lower the badge": every committed write that can change
/// the day picture calls `reconcile()` (or the cheaper `reconcileAfterIngest`
/// on the hot GPS path).
actor ReminderReconciler {
    private let scheduler: any LoggingReminderScheduling
    private let reportReader: ReportReader
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
    }

    /// How many days past today the per-day reminders are scheduled ahead, so a
    /// stretch where the app never runs still has reminders queued. Today plus
    /// this many days.
    static let defaultWindowDays = 6

    private static let logger = Logger(
        subsystem: "com.stuff.where",
        category: "ReminderReconciler",
    )

    init(
        scheduler: any LoggingReminderScheduling,
        reportReader: ReportReader,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        windowDays: Int = ReminderReconciler.defaultWindowDays,
    ) {
        self.scheduler = scheduler
        self.reportReader = reportReader
        self.calendar = calendar
        self.now = now
        self.windowDays = windowDays
    }

    /// Set the user's reminder intent (enabled + time of day), request
    /// notification permission when enabling, then reconcile the scheduled
    /// reminders and badge. Safe to call on every launch and whenever the user
    /// changes the setting.
    func configure(enabled: Bool, time: ReminderTime) async {
        config = Configuration(enabled: enabled, time: time)
        if enabled {
            _ = await scheduler.requestAuthorization()
        }
        await reconcile()
    }

    /// Explicitly drive the notification permission prompt (e.g. from a
    /// Settings toggle). Returns whether the app is authorized afterward.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await scheduler.requestAuthorization()
    }

    /// Whether the app is currently authorized to post reminders / set the
    /// badge, so the UI can surface an "open Settings" affordance.
    func isAuthorized() async -> Bool {
        await scheduler.isAuthorized()
    }

    /// Cheap reconcile for the GPS ingest path: only runs when reminders are on
    /// and today isn't already known to be covered, so a burst of
    /// significant-change samples doesn't trigger a full-year scan each time.
    func reconcileAfterIngest(changedDays: Set<Date>) async {
        guard config.enabled else { return }
        let today = calendar.startOfDay(for: now())
        let changedDayNeedsReconcile = changedDays.contains { $0 != today }
        guard todayCoveredByReconcile != today || changedDayNeedsReconcile else { return }
        await reconcile()
    }

    /// Recompute the current-year missing-day picture from the store and push
    /// it to the scheduler: the badge is the total unlogged days this year, and
    /// a rolling window of upcoming unlogged days gets per-day reminders.
    func reconcile() async {
        guard config.enabled else {
            await scheduler.reconcile(
                badgeCount: 0,
                scheduleDays: [],
                reminderTime: config.time,
                enabled: false,
            )
            todayCoveredByReconcile = nil
            return
        }

        let today = calendar.startOfDay(for: now())
        let year = calendar.component(.year, from: today)
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
            await scheduler.reconcile(
                badgeCount: backlog.count,
                scheduleDays: scheduleDays,
                reminderTime: config.time,
                enabled: true,
            )
            todayCoveredByReconcile = present.contains(today) ? today : nil
        } catch {
            Self.logger.error(
                "Failed to reconcile logging reminders: \(error.localizedDescription, privacy: .public)",
            )
        }
    }
}
