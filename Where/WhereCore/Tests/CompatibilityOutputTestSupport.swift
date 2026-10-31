import Foundation
@_spi(Testing) @testable import WhereCore

enum CompatibilityOutputTestSupport {
    typealias Gate = CompatibilityTestGate

    actor Scheduler: LoggingReminderScheduling, DailySummaryScheduling, DataIssueAlertScheduling {
        private(set) var enabled = false
        private(set) var badgeCount = 0
        private(set) var requests = 0
        private var nextPublicationGate: Gate?

        func holdNextPublication(_ gate: Gate) {
            nextPublicationGate = gate
        }

        func requestAuthorization() -> Bool {
            requests += 1; return true
        }

        func isAuthorized() -> Bool {
            true
        }

        func reconcile(
            badgeCount: Int,
            scheduleDays _: [Date],
            reminderTime _: ReminderTime,
            enabled: Bool,
        ) {
            self.badgeCount = badgeCount
            self.enabled = enabled
        }

        func reconcile(enabled: Bool, time _: ReminderTime, body _: String) async {
            if enabled, let gate = nextPublicationGate {
                nextPublicationGate = nil
                await gate.suspend()
            }
            self.enabled = enabled
        }
    }

    actor Widgets: WidgetTimelineRefreshing {
        private var nextCompatibilityError: (any Error)?
        private(set) var compatibility: [WidgetCompatibilitySnapshot] = []

        func failNextCompatibilityPublication(with error: any Error) {
            nextCompatibilityError = error
        }

        func publish(_: WidgetSnapshot) async {}

        func publishCompatibility(_ snapshot: WidgetCompatibilitySnapshot) throws {
            if let error = nextCompatibilityError {
                nextCompatibilityError = nil
                throw error
            }
            compatibility.append(snapshot)
        }
    }

    struct World {
        let store: SwiftDataStore
        let outputs: DataCompatibilityOutputs
        let reminders: Scheduler
        let summary: Scheduler
        let issues: Scheduler
        let widgets: Widgets
    }

    static func makeWorld() throws -> World {
        let store = try SwiftDataStore.inMemory()
        let reminders = Scheduler()
        let summary = Scheduler()
        let issues = Scheduler()
        let widgets = Widgets()
        let outputs = DataCompatibilityOutputs(
            reminders: reminders,
            summary: summary,
            issues: issues,
            widgets: widgets,
        )
        return World(
            store: store,
            outputs: outputs,
            reminders: reminders,
            summary: summary,
            issues: issues,
            widgets: widgets,
        )
    }
}
