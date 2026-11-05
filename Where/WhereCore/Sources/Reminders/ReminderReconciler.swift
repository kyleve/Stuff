import Foundation
import PeriscopeCore

/// Owns one evening schedule for locally enabled logging and historical issue categories.
/// Daily summaries remain independent. A failed refresh never publishes a false zero badge.
public actor ReminderReconciler {
    private let scheduler: any EveningReminderScheduling
    private let reportReader: ReportReader
    private let issueScanner: DataIssueScanner
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let windowDays: Int

    private struct Configuration {
        let enabled: Bool
        let time: ReminderTime
        let issueAlertsEnabled: Bool
        let driftThresholdMeters: Double

        var hasEnabledCategory: Bool {
            enabled || issueAlertsEnabled
        }
    }

    private var config: Configuration?
    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private struct ConfigurationID: Hashable { let value = UUID() }
    private var configurationID = ConfigurationID()
    private var todayCoveredByReconcile: Date?

    static let defaultWindowDays = 6
    private static let logger = WhereLog.reminders(ReminderReconcilerLog.self)

    init(
        scheduler: any EveningReminderScheduling,
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

    /// Callers distinguish enabling a category from disabling one or editing its time.
    /// Disabling must never cause a permission prompt for another enabled category.
    public func configure(
        enabled: Bool,
        time: ReminderTime,
        issueAlertsEnabled: Bool,
        driftThresholdMeters: Double,
        requestAuthorization: Bool,
    ) async {
        let previous = config
        let next = Configuration(
            enabled: enabled,
            time: time,
            issueAlertsEnabled: issueAlertsEnabled,
            driftThresholdMeters: driftThresholdMeters,
        )
        config = next
        let configuration = ConfigurationID()
        configurationID = configuration
        requestID = RequestID()
        // A prior request can contain a now-disabled category. Withdraw known-stale content
        // before reading history, even when a later scan fails. Preserve the unreadable badge.
        let removesCategory = previous.map {
            ($0.enabled && !enabled) || ($0.issueAlertsEnabled && !issueAlertsEnabled)
                || $0.time != time
        } ?? (!enabled || !issueAlertsEnabled)
        if removesCategory || !next.hasEnabledCategory {
            await scheduler.cancelScheduledReminders()
            guard configurationID == configuration, !Task.isCancelled else { return }
        }
        if requestAuthorization, next.hasEnabledCategory {
            _ = await scheduler.requestAuthorization()
        }
        // Permission is process-wide. If settings changed while the prompt was open,
        // reconcile the latest configuration instead of losing the successful grant.
        guard !Task.isCancelled else { return }
        await reconcile()
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        await scheduler.requestAuthorization()
    }

    public func isAuthorized() async -> Bool {
        await scheduler.isAuthorized()
    }

    /// New same-day GPS can create an issue even when today is recorded. Invalidate at the
    /// committed-ingest boundary instead of racing the scanner's asynchronous store listener.
    func reconcileAfterIngest(changedDays: Set<Date>) async {
        guard let config, config.hasEnabledCategory else { return }
        await issueScanner.invalidate()
        let today = calendar.startOfDay(for: now())
        guard config.issueAlertsEnabled || todayCoveredByReconcile != today
            || changedDays.contains(where: { $0 != today }) else { return }
        await reconcile()
    }

    func reconcile() async {
        guard let configuration = config else { return }
        let request = RequestID()
        requestID = request
        await Self.logger.measure(.reconcile, budget: .seconds(8)) {
            await performReconcile(configuration: configuration, request: request)
        }
    }

    private func performReconcile(configuration: Configuration, request: RequestID) async {
        do {
            let currentDate = now()
            let today = calendar.startOfDay(for: currentDate)
            let year = calendar.component(.year, from: today)
            let issueCount: Int = if configuration.issueAlertsEnabled {
                try await issueScanner.historicalScan(
                    driftThresholdMeters: configuration.driftThresholdMeters,
                    force: false,
                ).issueCount
            } else {
                0
            }
            guard requestID == request, !Task.isCancelled else { return }
            let present: Set<CalendarDay>
            let missingDayCount: Int
            if configuration.enabled {
                let report = try await reportReader.yearReport(for: year)
                present = Set(report.days.map(\.day))
                missingDayCount = MissingDays.missingDayKeys(
                    year: year,
                    through: MissingDays.backlogCutoff(asOf: currentDate, calendar: calendar),
                    present: present,
                ).count
            } else {
                present = []
                missingDayCount = 0
            }
            let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: today) ?? today
            let reminders = today.calendarDays(through: windowEnd, in: calendar).map { instant in
                let day = CalendarDay(from: instant, in: calendar)
                return EveningReminder(
                    day: day,
                    remindsToLogDay: configuration.enabled && !present.contains(day),
                    missingDayCount: missingDayCount,
                    issueCount: issueCount,
                )
            }.filter(\.hasWork)
            guard requestID == request, !Task.isCancelled else { return }
            await scheduler.reconcile(
                badgeCount: missingDayCount + issueCount,
                scheduleDays: reminders,
                reminderTime: configuration.time,
                enabled: configuration.hasEnabledCategory,
            )
            guard requestID == request else { return }
            todayCoveredByReconcile = present
                .contains(CalendarDay(from: today, in: calendar)) ? today : nil
        } catch {
            Self.logger.reconcileFailed(error: .restricted(.errorDetails, error))
        }
    }
}
