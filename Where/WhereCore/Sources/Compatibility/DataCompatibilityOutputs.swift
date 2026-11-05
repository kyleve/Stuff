import Foundation

/// Binds all history-derived system output to one access lifetime. Await retirement before
/// creating replacement services, so an old withdrawal cannot erase a new scope's publication.
public struct DataCompatibilityOutputs: Sendable {
    public let reminders: any LoggingReminderScheduling
    public let summary: any DailySummaryScheduling
    public let issues: any DataIssueAlertScheduling
    public let widgets: any WidgetTimelineRefreshing
    private let access: DataCompatibilityAccess
    private let queue: DataCompatibilityOutputQueue
    private let withdraw: @Sendable () async -> Void

    public init(
        access: DataCompatibilityAccess,
        reminders: any LoggingReminderScheduling,
        summary: any DailySummaryScheduling,
        issues: any DataIssueAlertScheduling,
        widgets: any WidgetTimelineRefreshing,
    ) {
        self.access = access
        let queue = DataCompatibilityOutputQueue(access: access)
        self.queue = queue
        self.reminders = Reminders(base: reminders, queue: queue)
        self.summary = Summary(base: summary, queue: queue)
        self.issues = Issues(base: issues, queue: queue)
        self.widgets = Widgets(base: widgets, queue: queue, access: access)
        withdraw = {
            await Self.withdraw(
                reminders: reminders,
                summary: summary,
                issues: issues,
                widgets: widgets,
            )
        }
    }

    /// Cold-start cleanup when no scope has submitted work in this process. Active scopes must
    /// use `retire()` so pending publications drain before removal.
    public static func withdraw(
        reminders: any LoggingReminderScheduling,
        summary: any DailySummaryScheduling,
        issues: any DataIssueAlertScheduling,
        widgets: any WidgetTimelineRefreshing,
    ) async {
        await reminders.reconcile(
            badgeCount: 0,
            scheduleDays: [],
            reminderTime: .defaultEvening,
            enabled: false,
        )
        await summary.reconcile(enabled: false, time: .defaultMorning, body: "")
        await issues.reconcile(enabled: false, time: .defaultEvening, body: "")
        await widgets.withdraw()
    }

    public func retire() async {
        access.revoke()
        await queue.retire(withdraw: withdraw)
    }

    private struct Reminders: LoggingReminderScheduling {
        let base: any LoggingReminderScheduling
        let queue: DataCompatibilityOutputQueue
        func requestAuthorization() async -> Bool {
            await base.requestAuthorization()
        }

        func isAuthorized() async -> Bool {
            await base.isAuthorized()
        }

        func cancelScheduledReminders() async {
            _ = await queue.publish { await base.cancelScheduledReminders() }
        }

        func reconcile(
            badgeCount: Int,
            scheduleDays: [Date],
            reminderTime: ReminderTime,
            enabled: Bool,
        ) async {
            _ = await queue.publish {
                await base.reconcile(
                    badgeCount: badgeCount,
                    scheduleDays: scheduleDays,
                    reminderTime: reminderTime,
                    enabled: enabled,
                )
            }
        }
    }

    private struct Summary: DailySummaryScheduling {
        let base: any DailySummaryScheduling
        let queue: DataCompatibilityOutputQueue
        func requestAuthorization() async -> Bool {
            await base.requestAuthorization()
        }

        func isAuthorized() async -> Bool {
            await base.isAuthorized()
        }

        func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
            _ = await queue
                .publish { await base.reconcile(enabled: enabled, time: time, body: body) }
        }
    }

    private struct Issues: DataIssueAlertScheduling {
        let base: any DataIssueAlertScheduling
        let queue: DataCompatibilityOutputQueue
        func requestAuthorization() async -> Bool {
            await base.requestAuthorization()
        }

        func isAuthorized() async -> Bool {
            await base.isAuthorized()
        }

        func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
            _ = await queue
                .publish { await base.reconcile(enabled: enabled, time: time, body: body) }
        }
    }

    private struct Widgets: WidgetTimelineRefreshing {
        let base: any WidgetTimelineRefreshing
        let queue: DataCompatibilityOutputQueue
        let access: DataCompatibilityAccess
        func publish(_ snapshot: WidgetSnapshot, access _: DataCompatibilityAccess?) async throws {
            let result: Result<Void, any Error>? = await queue.publish {
                do {
                    try await base.publish(snapshot, access: access)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
            guard let result else { throw DataAccessPermit.AccessError.revoked }
            try result.get()
        }

        func withdraw() async {
            _ = await queue.publish { await base.withdraw() }
        }
    }
}
