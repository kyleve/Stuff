import Foundation
import UserNotifications
@_spi(Testing) @testable import WhereCore

/// Exercises the production notification schedulers against delayed system acceptance.
actor CompatibilityNotificationCenter: NotificationReminderCenter {
    private var pending: [UNNotificationRequest] = []
    private var delivered: [String] = []
    private var nextAddGate: CompatibilityTestGate?
    private(set) var badge = 0

    func holdNextAdd(_ gate: CompatibilityTestGate) {
        nextAddGate = gate
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pending
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        delivered
    }

    func add(_ request: UNNotificationRequest) async throws {
        let gate = nextAddGate
        nextAddGate = nil
        await gate?.suspend()
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
        delivered.append(request.identifier)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        delivered.removeAll { identifiers.contains($0) }
    }

    func setBadgeCount(_ count: Int) async throws {
        badge = count
    }
}

actor CompatibilityWidgetRefresher: WidgetTimelineRefreshing {
    private(set) var snapshot: WidgetSnapshot?
    private(set) var withdrawalCount = 0
    private(set) var receivedAccess: DataCompatibilityAccess.ID?

    func publish(_ snapshot: WidgetSnapshot, access: DataCompatibilityAccess?) async {
        receivedAccess = access?.id
        self.snapshot = snapshot
    }

    func withdraw() async {
        withdrawalCount += 1
        snapshot = nil
    }
}

actor CompatibilityOutputTrace {
    enum Event: Equatable { case published, withdrawn, unexpected }
    private(set) var events: [Event] = []
    func append(_ event: Event) {
        events.append(event)
    }
}

enum CompatibilityOutputTestSupport {
    static func access() throws -> DataCompatibilityAccess {
        try DataCompatibilityAccess(
            base: SwiftDataStore.inMemory(),
            identity: .local(storeID: .init(rawValue: "output-fixture")),
            requiredMajor: 0,
            policy: .foundation,
            onFailure: { _, _ in },
        )
    }

    static func outputs(
        access: DataCompatibilityAccess,
        center: CompatibilityNotificationCenter,
        widgets: CompatibilityWidgetRefresher,
    ) -> DataCompatibilityOutputs {
        DataCompatibilityOutputs(
            access: access,
            reminders: UserNotificationReminderScheduler(
                notificationCenter: center,
                calendar: WhereCoreTestSupport.calendar(),
            ),
            summary: UserNotificationDailySummaryScheduler(notificationCenter: center),
            issues: UserNotificationDataIssueAlertScheduler(notificationCenter: center),
            widgets: widgets,
        )
    }
}
