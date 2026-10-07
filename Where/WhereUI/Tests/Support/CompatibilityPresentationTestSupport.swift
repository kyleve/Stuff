import Foundation
@_spi(Testing) import WhereCore
@testable import WhereUI

enum CompatibilityPresentationTestSupport {
    static let future = DataCompatibilityVersion(rawValue: 2)
    static func services(store: any WhereStore, source: any LocationSource) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: source,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    static func block(_ store: SwiftDataStore) async throws {
        await store.setSupportedDataCompatibilityVersionForTesting(future)
        try await store.perform { try await store.requireDataCompatibility(future) }
        await store.setSupportedDataCompatibilityVersionForTesting(.initial)
    }

    @MainActor static func waitUntil(_ condition: () async -> Bool) async throws {
        struct Timeout: Error {}
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await !condition() {
            if ContinuousClock.now >= deadline { throw Timeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
