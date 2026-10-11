import Foundation

extension DataCompatibilityOutputs {
    /// Process-owned adapters remain available to withdraw stale outputs even if store opening
    /// fails.
    public struct Destinations: Sendable {
        public let reminders: any LoggingReminderScheduling
        public let summary: any DailySummaryScheduling
        public let issues: any DataIssueAlertScheduling
        public let widgets: any WidgetTimelineRefreshing

        public init(
            reminders: any LoggingReminderScheduling,
            summary: any DailySummaryScheduling,
            issues: any DataIssueAlertScheduling,
            widgets: any WidgetTimelineRefreshing,
        ) {
            self.reminders = reminders
            self.summary = summary
            self.issues = issues
            self.widgets = widgets
        }

        public func withdraw() async {
            do { try await widgets.publishCompatibility(.init(requiredVersion: nil)) }
            catch {
                WhereLog.root(DataCompatibilityLog.self)(attachments: [.error(
                    error,
                    name: "widget-withdrawal-error",
                )]) {
                    .accessBlocked(description: error.localizedDescription)
                }
            }
            async let clearedReminders: Void = reminders.reconcile(
                badgeCount: 0,
                scheduleDays: [],
                reminderTime: .defaultEvening,
                enabled: false,
            )
            async let clearedSummary: Void = summary.reconcile(
                enabled: false,
                time: .defaultMorning,
                body: "",
            )
            async let clearedIssues: Void = issues.reconcile(
                enabled: false,
                time: .defaultEvening,
                body: "",
            )
            _ = await (clearedReminders, clearedSummary, clearedIssues)
        }
    }
}
