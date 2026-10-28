import Foundation
import Testing
import UserNotifications
@testable import WhereCore

struct UserNotificationDataIssueAlertSchedulerTests {
    private static let identifier = "com.stuff.where.data-issues"

    @Test func schedulesRepeatingTriggerAtConfiguredTime() async throws {
        let center = FakeIssueAlertCenter()
        let scheduler = UserNotificationDataIssueAlertScheduler(notificationCenter: center)

        await scheduler.reconcile(
            enabled: true,
            time: ReminderTime(hour: 18, minute: 30),
            body: "3 issues to resolve",
        )

        let request = try #require(center.pendingRequests.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.hour == 18)
        #expect(trigger.dateComponents.minute == 30)
        #expect(request.identifier == Self.identifier)
        #expect(request.content.body == "3 issues to resolve")
    }

    @Test func unchangedReconcileDoesNotReschedule() async {
        let center = FakeIssueAlertCenter()
        let scheduler = UserNotificationDataIssueAlertScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 18, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "1 issue to resolve")
        await scheduler.reconcile(enabled: true, time: time, body: "1 issue to resolve")

        #expect(center.addedRequests.count == 1)
    }

    @Test func changingBodyReplacesExistingRequest() async throws {
        let center = FakeIssueAlertCenter()
        let scheduler = UserNotificationDataIssueAlertScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 18, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "1 issue to resolve")
        await scheduler.reconcile(enabled: true, time: time, body: "2 issues to resolve")

        let updated = try #require(center.pendingRequests.first)
        #expect(updated.content.body == "2 issues to resolve")
        #expect(center.addedRequests.count == 2)
    }

    @Test func strayDuplicatesAreRebuiltIntoASingleRequest() async throws {
        let center = FakeIssueAlertCenter()
        let scheduler = UserNotificationDataIssueAlertScheduler(notificationCenter: center)
        let content = UNMutableNotificationContent()
        try await center.add(UNNotificationRequest(
            identifier: "\(Self.identifier).legacy-1",
            content: content,
            trigger: nil,
        ))
        try await center.add(UNNotificationRequest(
            identifier: "\(Self.identifier).legacy-2",
            content: content,
            trigger: nil,
        ))

        await scheduler.reconcile(
            enabled: true,
            time: ReminderTime(hour: 18, minute: 0),
            body: "1 issue to resolve",
        )

        #expect(center.pendingRequests.count == 1)
        #expect(center.pendingRequests.first?.identifier == Self.identifier)
        #expect(center.removedPendingIdentifiers.contains("\(Self.identifier).legacy-1"))
        #expect(center.removedPendingIdentifiers.contains("\(Self.identifier).legacy-2"))
    }

    @Test func disablingClearsOwnedRequest() async {
        let center = FakeIssueAlertCenter()
        let scheduler = UserNotificationDataIssueAlertScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 18, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "1 issue to resolve")
        #expect(center.pendingRequests.count == 1)

        await scheduler.reconcile(enabled: false, time: time, body: "1 issue to resolve")
        #expect(center.pendingRequests.isEmpty)
    }

    @Test func deniedAuthorizationClearsOwnedRequest() async {
        let center = FakeIssueAlertCenter()
        let scheduler = UserNotificationDataIssueAlertScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 18, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "1 issue to resolve")
        #expect(center.pendingRequests.count == 1)

        center.status = .denied
        await scheduler.reconcile(enabled: true, time: time, body: "1 issue to resolve")
        #expect(center.pendingRequests.isEmpty)
    }
}

private final class FakeIssueAlertCenter: NotificationReminderCenter, @unchecked Sendable {
    var status: UNAuthorizationStatus = .authorized
    private(set) var pendingRequests: [UNNotificationRequest] = []
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [String] = []
    private var deliveredIdentifiers: [String] = []

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        switch status {
            case .authorized, .provisional, .ephemeral:
                true
            case .notDetermined, .denied:
                false
            @unknown default:
                false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingRequests
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        deliveredIdentifiers
    }

    func add(_ request: UNNotificationRequest) async throws {
        pendingRequests.removeAll { $0.identifier == request.identifier }
        pendingRequests.append(request)
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedPendingIdentifiers.append(contentsOf: identifiers)
        pendingRequests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        deliveredIdentifiers.removeAll { identifiers.contains($0) }
    }

    func setBadgeCount(_: Int) async throws {}
}
