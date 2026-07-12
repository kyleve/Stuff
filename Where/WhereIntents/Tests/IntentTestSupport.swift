import Foundation
import WhereCore
@testable import WhereIntents

/// Shared fixtures for the WhereIntents suites: an in-memory `WhereServices`
/// wired exactly like `WhereServices.forIntents()` (an `IdleLocationSource`, no
/// GPS) but over `SwiftDataStore.inMemory()` and with no-op notification /
/// widget side effects, plus a fixed Pacific calendar so day/year math is
/// deterministic regardless of the host time zone.
enum IntentTestSupport {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar
    }

    static func iso(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else {
            fatalError("Invalid ISO-8601 date in test fixture: \(string)")
        }
        return date
    }

    /// In-memory services matching the intent stack: idle location source,
    /// Pacific aggregator, no-op schedulers/refresher.
    static func services(
        store: SwiftDataStore,
        now: @escaping @Sendable () -> Date = { Date() },
    ) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: IdleLocationSource(),
            aggregator: DayAggregator(calendar: calendar(), timeZone: pacific),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: now,
        )
    }
}
