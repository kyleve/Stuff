import Foundation

/// Prepared before ordinary services so cold launches can inspect and withdraw incompatible data.
public struct DataCompatibilityServices: Sendable {
    public let coordinator: DataCompatibilityCoordinator
    public let outputs: DataCompatibilityOutputs

    public init(
        store: any WhereStore,
        currentDeviceID: RecordingDeviceID,
        reminderScheduler: any LoggingReminderScheduling,
        summaryScheduler: any DailySummaryScheduling,
        issueAlertScheduler: any DataIssueAlertScheduling,
        widgetRefresher: any WidgetTimelineRefreshing,
    ) {
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            currentDeviceID: currentDeviceID,
        )
        self.coordinator = coordinator
        outputs = DataCompatibilityOutputs(
            compatibility: coordinator,
            reminderScheduler: reminderScheduler,
            summaryScheduler: summaryScheduler,
            issueAlertScheduler: issueAlertScheduler,
            widgetRefresher: widgetRefresher,
        )
    }
}
