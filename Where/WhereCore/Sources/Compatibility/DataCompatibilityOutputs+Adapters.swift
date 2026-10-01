import Foundation

extension DataCompatibilityOutputs {
    nonisolated var reminders: any LoggingReminderScheduling {
        CompatibleReminders(base: reminderScheduler, outputs: self)
    }

    nonisolated var summary: any DailySummaryScheduling {
        CompatibleSummary(base: summaryScheduler, outputs: self)
    }

    nonisolated var issueAlerts: any DataIssueAlertScheduling {
        CompatibleIssueAlerts(base: issueAlertScheduler, outputs: self)
    }

    nonisolated var widgets: any WidgetTimelineRefreshing {
        CompatibleWidgets(base: widgetRefresher, outputs: self)
    }
}

private struct CompatibleReminders: LoggingReminderScheduling {
    let base: any LoggingReminderScheduling
    let outputs: DataCompatibilityOutputs
    func requestAuthorization() async -> Bool {
        await outputs
            .authorize { await base.requestAuthorization() }
    }

    func isAuthorized() async -> Bool {
        await base.isAuthorized()
    }

    func reconcile(
        badgeCount: Int,
        scheduleDays: [Date],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        await outputs.publish { _ in
            await base.reconcile(
                badgeCount: badgeCount,
                scheduleDays: scheduleDays,
                reminderTime: reminderTime,
                enabled: enabled,
            )
        }
    }
}

private struct CompatibleSummary: DailySummaryScheduling {
    let base: any DailySummaryScheduling
    let outputs: DataCompatibilityOutputs
    func requestAuthorization() async -> Bool {
        await outputs
            .authorize { await base.requestAuthorization() }
    }

    func isAuthorized() async -> Bool {
        await base.isAuthorized()
    }

    func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
        await outputs
            .publish { _ in await base.reconcile(enabled: enabled, time: time, body: body) }
    }
}

private struct CompatibleIssueAlerts: DataIssueAlertScheduling {
    let base: any DataIssueAlertScheduling
    let outputs: DataCompatibilityOutputs
    func requestAuthorization() async -> Bool {
        await outputs
            .authorize { await base.requestAuthorization() }
    }

    func isAuthorized() async -> Bool {
        await base.isAuthorized()
    }

    func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
        await outputs
            .publish { _ in await base.reconcile(enabled: enabled, time: time, body: body) }
    }
}

private struct CompatibleWidgets: WidgetTimelineRefreshing {
    let base: any WidgetTimelineRefreshing
    let outputs: DataCompatibilityOutputs

    func publish(_ snapshot: WidgetSnapshot) async throws {
        let result = await outputs.publish { status in
            try await base.publishCompatibility(.init(requiredVersion: nil))
            try await base.publish(snapshot)
            // Only freshly computed data can reopen the widget after a blocked state.
            try await base.publishCompatibility(.init(requiredVersion: status.requiredVersion))
        }
        try result.get()
    }

    func publishCompatibility(_: WidgetCompatibilitySnapshot) async {
        await outputs.withdraw()
    }
}
