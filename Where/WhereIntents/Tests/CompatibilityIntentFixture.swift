import Foundation
@_spi(Testing) import WhereCore

/// Admitted services on isolated local data, so intent tests can retire the actual permit.
@MainActor
struct CompatibilityIntentFixture {
    let access: DataCompatibilityAccess
    let services: WhereServices

    init() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: .init(rawValue: "intent-fixture")),
            policy: .foundation,
            activationReadiness: .pendingValidation,
        )
        access = try await coordinator.refresh()
        services = try await WhereServices.make(
            access: access,
            locationSource: IdleLocationSource(),
            installationContext: .testing,
            aggregator: DayAggregator(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
            importRecoveryPersistence: NoopBackupImportRecoveryPersistence(),
            now: Date.init,
        )
    }
}
