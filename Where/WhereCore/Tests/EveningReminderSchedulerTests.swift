import Foundation
import Testing
import UserNotifications
@testable import WhereCore

struct EveningReminderSchedulerTests {
    @Test func oneDailyRequestCombinesCountsAndReplacesChangedContent() async throws {
        let center = FakeNotificationReminderCenter()
        let scheduler = UserNotificationReminderScheduler(notificationCenter: center)
        let day = CalendarDay(year: 2026, month: 1, day: 5)
        let combined = EveningReminder(
            day: day,
            remindsToLogDay: true,
            missingDayCount: 2,
            issueCount: 3,
        )
        await scheduler.reconcile(
            badgeCount: 5,
            scheduleDays: [combined, combined],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        let first = try #require(center.pendingRequests.first)
        #expect(center.pendingRequests.count == 1)
        #expect(first.content.body.contains("2 earlier days"))
        #expect(first.content.body.contains("3 issues"))
        let remaining = EveningReminder(
            day: day,
            remindsToLogDay: false,
            missingDayCount: 0,
            issueCount: 1,
        )
        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [remaining],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        let updated = try #require(center.pendingRequests.first)
        #expect(updated.identifier == first.identifier)
        #expect(updated.content.body == "1 issue to resolve")
        #expect(center.addedRequests.count == 2)
        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [remaining],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        #expect(center.addedRequests.count == 2)
    }

    @Test func obsoleteIssueAlertIsRemovedWhileTheDailySummaryRemains() async throws {
        let center = FakeNotificationReminderCenter()
        let scheduler = UserNotificationReminderScheduler(notificationCenter: center)
        let oldID = "com.stuff.where.data-issues"
        let summaryID = "com.stuff.where.daily-summary"
        for notificationID in [oldID, summaryID] {
            try await center.add(UNNotificationRequest(
                identifier: notificationID,
                content: UNMutableNotificationContent(),
                trigger: nil,
            ))
        }
        center.deliveredIdentifiers = [oldID, summaryID]
        let remaining = EveningReminder(
            day: CalendarDay(year: 2026, month: 1, day: 5),
            remindsToLogDay: false,
            missingDayCount: 0,
            issueCount: 2,
        )
        await scheduler.reconcile(
            badgeCount: 2,
            scheduleDays: [remaining],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        #expect(center.pendingRequests.count == 2)
        #expect(center.pendingRequests.contains { $0.identifier == oldID } == false)
        #expect(center.pendingRequests.contains { $0.identifier == summaryID })
        #expect(center.deliveredIdentifiers == [summaryID])
    }

    @Test func cancellingLoggingPreservesTheIndependentBadgeAndOtherNotifications() async throws {
        let center = FakeNotificationReminderCenter()
        let scheduler = UserNotificationReminderScheduler(
            notificationCenter: center,
        )
        let day = try #require(Self.calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 5,
        )))
        await scheduler.reconcile(
            badgeCount: 7,
            scheduleDays: [Self.reminder(day)],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        let other = UNNotificationRequest(
            identifier: "separate-summary",
            content: UNMutableNotificationContent(),
            trigger: nil,
        )
        try await center.add(other)
        await scheduler.cancelScheduledReminders()
        #expect(center.pendingRequests.map(\.identifier) == [other.identifier])
        #expect(center.badgeCounts == [7])
    }

    private static func reminder(_ day: Date) -> EveningReminder {
        EveningReminder(
            day: CalendarDay(from: day, in: calendar),
            remindsToLogDay: true,
            missingDayCount: 0,
            issueCount: 0,
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    @Test func changingReminderTimeReplacesExistingPendingRequest() async throws {
        let center = FakeNotificationReminderCenter()
        let scheduler = UserNotificationReminderScheduler(
            notificationCenter: center,
        )
        let day = try #require(Self.calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 5,
        )))

        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [Self.reminder(day)],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        let firstRequest = try #require(center.pendingRequests.first)
        #expect(firstRequest.reminderHour == 20)
        #expect(firstRequest.reminderMinute == 0)

        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [Self.reminder(day)],
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
        )
        let day = try #require(Self.calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 5,
        )))

        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [Self.reminder(day)],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        #expect(center.pendingRequests.count == 1)
        #expect(center.badgeCounts.last == 1)

        center.status = .denied
        await scheduler.reconcile(
            badgeCount: 1,
            scheduleDays: [Self.reminder(day)],
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
    var deliveredIdentifiers: [String] = []

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        switch status {
            case .notDetermined, .denied:
                false
            case .authorized, .provisional, .ephemeral:
                true
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

    func setBadgeCount(_ count: Int) async throws {
        badgeCounts.append(count)
    }
}
