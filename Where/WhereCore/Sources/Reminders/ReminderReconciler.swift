import Foundation
import PeriscopeCore
import RegionKit

/// Owns the daily "log before the day ends" reminder intent and the
/// reconciliation that keeps the scheduled reminders + badge in sync with the
/// current year's missing days and all historical unresolved issues.
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
    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private struct ConfigurationID: Hashable { let value = UUID() }
    private var configurationID = ConfigurationID()

    /// The start-of-day we last reconciled while today already had presence.
    /// Lets the GPS ingest path skip a full report read when issue alerts are disabled.
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

    private static let logger = WhereLog.reminders(ReminderReconcilerLog.self)

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
        let configuration = ConfigurationID()
        configurationID = configuration
        requestID = RequestID()
        if enabled {
            _ = await scheduler.requestAuthorization()
        }
        guard configurationID == configuration, !Task.isCancelled else { return }
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

    /// Reconcile after committed GPS ingestion. Enabled issues require fresh assessment even
    /// when today is already covered. With issues disabled, covered same-day writes can skip
    /// the report read. Invalidate inline instead of racing the store-change listener.
    func reconcileAfterIngest(changedDays: Set<Date>) async {
        guard config.enabled || config.issueAlertsEnabled else { return }
        // This is a committed-ingest boundary. Do not race the scanner's asynchronous listener.
        await issueScanner.invalidate()
        let today = calendar.startOfDay(for: now())
        let changedDayNeedsReconcile = changedDays.contains { $0 != today }
        // A new point can create a conflict even on an already recorded day.
        guard config
            .issueAlertsEnabled || todayCoveredByReconcile != today || changedDayNeedsReconcile
        else { return }
        await reconcile()
    }

    /// Recompute the current-year missing-day picture from the store and push
    /// it to the scheduler: the badge is the total unlogged days this year plus
    /// the unresolved data-issue count, and a rolling window of upcoming unlogged
    /// days gets per-day reminders.
    func reconcile() async {
        let request = RequestID()
        requestID = request
        let configuration = config
        await Self.logger.measure(.reconcile, budget: .seconds(8)) {
            await performReconcile(configuration: configuration, request: request)
        }
    }

    /// `reconcile()`'s body, split out so the span wraps every path through it —
    /// including the reminders-off branch, which still scans for the badge.
    private func performReconcile(configuration: Configuration, request: RequestID) async {
        let today = calendar.startOfDay(for: now())
        let year = calendar.component(.year, from: today)

        do {
            if !configuration.enabled {
                guard requestID == request, !Task.isCancelled else { return }
                // Apply known disabled intent even if the independent issue count cannot load.
                await scheduler.cancelScheduledReminders()
                guard requestID == request, !Task.isCancelled else { return }
                todayCoveredByReconcile = nil
            }
            let issueBadge = try await dataIssueBadgeCount(configuration: configuration)
            guard requestID == request, !Task.isCancelled else { return }
            guard configuration.enabled else {
                await scheduler.reconcile(
                    badgeCount: issueBadge,
                    scheduleDays: [],
                    reminderTime: configuration.time,
                    enabled: false,
                )
                guard requestID == request else { return }
                todayCoveredByReconcile = nil
                return
            }

            let report = try await reportReader.yearReport(for: year)
            let present = Set(report.days.map(\.day))
            // The badge backlog is *past* misses only — today is still loggable,
            // so it's covered by the forward-looking reminder below rather than
            // counted as missed (otherwise the app would warn every morning).
            let backlog = MissingDays.missingDayKeys(
                year: year,
                through: MissingDays.backlogCutoff(asOf: now(), calendar: calendar),
                present: present,
            )
            let windowEnd = calendar.date(
                byAdding: .day,
                value: windowDays,
                to: today,
            ) ?? today
            let scheduleDays = today
                .calendarDays(through: windowEnd, in: calendar)
                .filter { !present.contains(CalendarDay(from: $0, in: calendar)) }
            guard requestID == request, !Task.isCancelled else { return }
            await scheduler.reconcile(
                badgeCount: backlog.count + issueBadge,
                scheduleDays: scheduleDays,
                reminderTime: configuration.time,
                enabled: true,
            )
            guard requestID == request else { return }
            todayCoveredByReconcile = present.contains(CalendarDay(from: today, in: calendar))
                ? today
                : nil
        } catch {
            Self.logger.reconcileFailed(
                error: .restricted(.errorDetails, error),
            )
        }
    }

    /// One failed historical scan leaves the previous schedule and badge intact.
    /// Unknown recording dates and cross-year concerns are counted once by the shared scan.
    private func dataIssueBadgeCount(configuration: Configuration) async throws -> Int {
        guard configuration.issueAlertsEnabled else { return 0 }
        let result = try await issueScanner.historicalScan(
            driftThresholdMeters: configuration.driftThresholdMeters,
            force: false,
        )
        return result.issueCount
    }
}
