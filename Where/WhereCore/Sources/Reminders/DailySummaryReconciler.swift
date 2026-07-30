import Foundation
import PeriscopeCore
import RegionKit

/// Owns the daily summary recap intent and the reconciliation that recomputes
/// the year-to-date recap text and pushes it to the summary scheduler.
public actor DailySummaryReconciler {
    private let scheduler: any DailySummaryScheduling
    private let reportReader: ReportReader
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let regionLimit: Int

    private var config = Configuration()

    private struct Configuration {
        var enabled = false
        var time: ReminderTime = .defaultMorning
    }

    /// How many top regions the daily summary recap lists, so the notification
    /// body stays short.
    static let defaultRegionLimit = 3

    private static let logger = WhereLog.reminders(DailySummaryReconcilerLog.self)

    init(
        scheduler: any DailySummaryScheduling,
        reportReader: ReportReader,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        regionLimit: Int = DailySummaryReconciler.defaultRegionLimit,
    ) {
        self.scheduler = scheduler
        self.reportReader = reportReader
        self.calendar = calendar
        self.now = now
        self.regionLimit = regionLimit
    }

    /// Set the user's daily-summary intent (enabled + time of day), request
    /// notification permission when enabling, then reconcile the scheduled
    /// summary notification. Safe to call on every launch and whenever the user
    /// changes the setting.
    public func configure(enabled: Bool, time: ReminderTime) async {
        config = Configuration(enabled: enabled, time: time)
        if enabled {
            _ = await scheduler.requestAuthorization()
        }
        await reconcile()
    }

    /// Recompute the year-to-date recap text from the current year's data and
    /// push it to the summary scheduler. When disabled, the owned notification
    /// is cleared.
    func reconcile() async {
        await Self.logger.measure(.reconcile, budget: .seconds(2)) {
            guard config.enabled else {
                await scheduler.reconcile(enabled: false, time: config.time, body: "")
                return
            }

            let year = calendar.component(.year, from: now())
            do {
                let report = try await reportReader.yearReport(for: year)
                await scheduler.reconcile(
                    enabled: true,
                    time: config.time,
                    body: summaryBody(for: report),
                )
            } catch {
                Self.logger(attachments: [.error(error, name: "reconcile-error")]) {
                    .reconcileFailed(description: error.localizedDescription)
                }
            }
        }
    }

    /// Build the recap notification body from a year's totals: the top regions
    /// by day count, e.g. "132 days in California, 40 days in New York". Falls
    /// back to an empty-state line when nothing has been logged yet.
    private func summaryBody(for report: YearReport) -> String {
        let ranked = Region.rankedByDayCount(
            report.totals.filter { $0.value > 0 },
            days: { $0.value },
            region: { $0.key },
        )
        .prefix(regionLimit)

        guard !ranked.isEmpty else {
            return String(localized: .summaryNotificationBodyEmpty)
        }

        return ranked
            .map { Self.summaryFragment(region: $0.key, days: $0.value) }
            .joined(separator: ", ")
    }

    private static func summaryFragment(region: Region, days: Int) -> String {
        let count = String(localized: .summaryNotificationDayCount(days))
        return String(localized: .summaryNotificationRegionDays(count, region.localizedName))
    }
}
