import Foundation
import Testing
import UserNotifications
@testable import WhereCore

struct LoggingReminderSchedulerTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    @Test func changingReminderTimeReplacesExistingPendingRequest() async throws {
        let center = FakeNotificationReminderCenter()
        let scheduler = UserNotificationReminderScheduler(
            notificationCenter: center,
            calendar: Self.calendar,
        )
        let day = try #require(Self.calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 5,
        )))

        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [day],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        let firstRequest = try #require(center.pendingRequests.first)
        #expect(firstRequest.reminderHour == 20)
        #expect(firstRequest.reminderMinute == 0)

        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [day],
            reminderTime: ReminderTime(hour: 7, minute: 30),
            enabled: true,
        )

        let updatedRequest = try #require(center.pendingRequests.first)
        #expect(updatedRequest.identifier == firstRequest.identifier)
        #expect(updatedRequest.reminderHour == 7)
        #expect(updatedRequest.reminderMinute == 30)
        #expect(center.addedRequests.count == 2)
        #expect(center.removedPendingIdentifiers.contains(firstRequest.identifier))
    }

    @Test func revokedAuthorizationClearsOwnedRequestsAndBadge() async throws {
        let center = FakeNotificationReminderCenter()
        let scheduler = UserNotificationReminderScheduler(
            notificationCenter: center,
            calendar: Self.calendar,
        )
        let day = try #require(Self.calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 5,
        )))

        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [day],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        #expect(center.pendingRequests.count == 1)
        #expect(center.badgeCounts.last == 1)

        center.status = .denied
        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [day],
            reminderTime: .defaultEvening,
            enabled: true,
        )

        #expect(center.pendingRequests.isEmpty)
        #expect(center.badgeCounts.last == 0)
    }
}

extension UNNotificationRequest {
    fileprivate var reminderHour: Int? {
        (trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour
    }

    fileprivate var reminderMinute: Int? {
        (trigger as? UNCalendarNotificationTrigger)?.dateComponents.minute
    }
}

private final class FakeNotificationReminderCenter: NotificationReminderCenter,
    @unchecked Sendable
{
    var status: UNAuthorizationStatus = .authorized
    private(set) var pendingRequests: [UNNotificationRequest] = []
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [String] = []
    private(set) var badgeCounts: [Int] = []
    private var deliveredIdentifiers: [String] = []

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        switch status {
            case .authorized, .provisional, .ephemeral:
                true
            default:
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

    func setBadgeCount(_ count: Int) async throws {
        badgeCounts.append(count)
    }
}
