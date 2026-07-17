import Foundation
@_spi(Testing) import WhereCore
@testable import WhereIntents

/// Shared fixtures for the WhereIntents suites: an in-memory `WhereServices`
/// wired exactly like `WhereServices.forIntents()` (an `IdleLocationSource`, no
/// GPS) but over `SwiftDataStore.inMemory()` and with no-op notification /
/// widget side effects, plus a fixed Pacific calendar so day/year math is
/// deterministic regardless of the host time zone.
struct IntentWaitTimeout: Error {}

/// Polls the async `predicate` until it holds or the timeout elapses, yielding
/// between checks — condition-based waiting for actor-isolated state (e.g.
/// `IntentServices.waiterCount`).
func waitUntil(
    timeout: Duration = .seconds(5),
    _ predicate: () async -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while await !predicate() {
        if ContinuousClock.now >= deadline { throw IntentWaitTimeout() }
        try await Task.sleep(for: .milliseconds(1))
    }
}

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
