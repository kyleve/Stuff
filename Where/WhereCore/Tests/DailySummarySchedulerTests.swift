import Foundation
import Testing
import UserNotifications
@testable import WhereCore

struct DailySummarySchedulerTests {
    @Test func schedulesRepeatingTriggerAtConfiguredTime() async throws {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)

        await scheduler.reconcile(
            enabled: true,
            time: ReminderTime(hour: 8, minute: 0),
            body: "132 days in California",
        )

        let request = try #require(center.pendingRequests.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.hour == 8)
        #expect(trigger.dateComponents.minute == 0)
        #expect(request.content.body == "132 days in California")
    }

    @Test func unchangedReconcileDoesNotReschedule() async {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 8, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "same body")
        await scheduler.reconcile(enabled: true, time: time, body: "same body")

        #expect(center.addedRequests.count == 1)
    }

    @Test func changingTimeReplacesExistingRequest() async throws {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)

        await scheduler.reconcile(
            enabled: true,
            time: ReminderTime(hour: 8, minute: 0),
            body: "body",
        )
        let first = try #require(center.pendingRequests.first)

        await scheduler.reconcile(
            enabled: true,
            time: ReminderTime(hour: 9, minute: 30),
            body: "body",
        )

        let updated = try #require(center.pendingRequests.first)
        let trigger = try #require(updated.trigger as? UNCalendarNotificationTrigger)
        #expect(updated.identifier == first.identifier)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 30)
        #expect(center.addedRequests.count == 2)
        #expect(center.removedPendingIdentifiers.contains(first.identifier))
    }

    @Test func changingBodyReplacesExistingRequest() async throws {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 8, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "old")
        await scheduler.reconcile(enabled: true, time: time, body: "new")

        let updated = try #require(center.pendingRequests.first)
        #expect(updated.content.body == "new")
        #expect(center.addedRequests.count == 2)
    }

    @Test func strayDuplicatesAreRebuiltIntoASingleRequest() async throws {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)
        // Two owned-but-stale requests (e.g. left by an older identifier scheme)
        // force a full rebuild rather than the leave-it-in-place fast path.
        let content = UNMutableNotificationContent()
        try await center.add(UNNotificationRequest(
            identifier: "com.stuff.where.daily-summary.legacy-1",
            content: content,
            trigger: nil,
        ))
        try await center.add(UNNotificationRequest(
            identifier: "com.stuff.where.daily-summary.legacy-2",
            content: content,
            trigger: nil,
        ))

        await scheduler.reconcile(
            enabled: true,
            time: ReminderTime(hour: 8, minute: 0),
            body: "body",
        )

        #expect(center.pendingRequests.count == 1)
        #expect(center.pendingRequests.first?.identifier == "com.stuff.where.daily-summary")
        #expect(center.removedPendingIdentifiers.contains("com.stuff.where.daily-summary.legacy-1"))
        #expect(center.removedPendingIdentifiers.contains("com.stuff.where.daily-summary.legacy-2"))
    }

    @Test func disablingClearsOwnedRequest() async {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 8, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "body")
        #expect(center.pendingRequests.count == 1)

        await scheduler.reconcile(enabled: false, time: time, body: "body")
        #expect(center.pendingRequests.isEmpty)
    }

    @Test func deniedAuthorizationClearsOwnedRequest() async {
        let center = FakeSummaryCenter()
        let scheduler = UserNotificationDailySummaryScheduler(notificationCenter: center)
        let time = ReminderTime(hour: 8, minute: 0)

        await scheduler.reconcile(enabled: true, time: time, body: "body")
        #expect(center.pendingRequests.count == 1)

        center.status = .denied
        await scheduler.reconcile(enabled: true, time: time, body: "body")
        #expect(center.pendingRequests.isEmpty)
    }
}

private final class FakeSummaryCenter: NotificationReminderCenter, @unchecked Sendable {
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
