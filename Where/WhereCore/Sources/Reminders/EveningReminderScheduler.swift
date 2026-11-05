import Foundation
import PeriscopeCore
import UserNotifications

/// Time of day (in the user's calendar) at which the daily "log before the day
/// ends" reminder fires. Defaults to 8 PM.
public struct ReminderTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// 8 PM — late enough that a passive day's GPS has usually landed, early
    /// enough to still act before midnight.
    public static let defaultEvening = ReminderTime(hour: 20, minute: 0)

    /// 8 AM — a morning slot for the daily summary recap, after the previous
    /// day has fully settled.
    public static let defaultMorning = ReminderTime(hour: 8, minute: 0)
}

/// Schedules combined evening work and the app-icon badge. The protocol lets
/// `ReminderReconciler` drive the same publication boundary in production and tests.
public protocol EveningReminderScheduling: Sendable {
    /// Ask the system for permission to post alerts/sounds/badges. Returns
    /// whether the app is authorized afterward. Safe to call repeatedly.
    func requestAuthorization() async -> Bool

    /// Whether the app is currently authorized to post notifications and set
    /// the badge. Lets the UI route the user to Settings when they've enabled
    /// reminders but denied the system permission.
    func isAuthorized() async -> Bool

    /// Cancel owned evening requests without changing the last assessed badge.
    /// This applies known disabled intent when history is temporarily unreadable.
    func cancelScheduledReminders() async

    /// Publish one combined request per requested calendar day and the assessed badge.
    /// Empty work is omitted. Refresh existing requests when their time or content changes.
    /// Disabled schedules remove owned requests, including the superseded issue-alert ID.
    /// Badge count is explicit; cancellation without a fresh count uses `cancelScheduledReminders`.
    func reconcile(
        badgeCount: Int,
        scheduleDays: [EveningReminder],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async
}

/// An `EveningReminderScheduling` that does nothing. For SwiftUI previews,
/// view-model tests, and demo mode — anything that needs a reconciler without
/// touching `UNUserNotificationCenter`.
///
/// - Parameter authorized: what it reports back. Defaults to *un*authorized, so
///   the UI's "denied" affordances stay exercisable in previews and tests. Demo
///   mode passes `true`: it presents a fully-granted user (as its location
///   source does), and a scheduler claiming denial there would both log a
///   spurious warning and offer a dead-end trip to the Settings app.
public struct NoopEveningReminderScheduler: EveningReminderScheduling {
    private let authorized: Bool

    public init(authorized: Bool = false) {
        self.authorized = authorized
    }

    public func requestAuthorization() async -> Bool {
        authorized
    }

    public func isAuthorized() async -> Bool {
        authorized
    }

    public func cancelScheduledReminders() async {}

    public func reconcile(
        badgeCount _: Int,
        scheduleDays _: [EveningReminder],
        reminderTime _: ReminderTime,
        enabled _: Bool,
    ) async {}
}

/// Production `EveningReminderScheduling` backed by `UNUserNotificationCenter`.
/// Only touches notification requests it owns (matched by identifier prefix) so
/// it never disturbs notifications from elsewhere in the app.
public final class UserNotificationReminderScheduler: EveningReminderScheduling,
    @unchecked Sendable
{
    private let center: any NotificationReminderCenter

    private static let identifierPrefix = "com.stuff.where.logging-reminder"
    private static let logger = WhereLog.reminders(LoggingReminderSchedulerLog.self)

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = UNUserNotificationCenterAdapter(center: center)
    }

    init(notificationCenter: any NotificationReminderCenter) {
        center = notificationCenter
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.logger.authorizationRequestFailed(
                error: .restricted(.errorDetails, error),
            )
            return false
        }
    }

    public func isAuthorized() async -> Bool {
        switch await center.authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                true
            case .notDetermined, .denied:
                false
            @unknown default:
                false
        }
    }

    public func cancelScheduledReminders() async {
        await removeAllOwnedReminders()
    }

    public func reconcile(
        badgeCount: Int,
        scheduleDays: [EveningReminder],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        await Self.logger.measure(.reconcileNotifications, budget: .seconds(1)) {
            await performReconcile(
                badgeCount: badgeCount,
                scheduleDays: scheduleDays,
                reminderTime: reminderTime,
                enabled: enabled,
            )
        }
    }

    /// `reconcile`'s body, split out so the span covers every path — including
    /// the disabled one, which still walks both notification sets to remove what
    /// it owns.
    private func performReconcile(
        badgeCount: Int,
        scheduleDays: [EveningReminder],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        guard enabled else {
            // Reminders are off, but the badge may still carry a decoupled
            // data-issue count (see `ReminderReconciler`), so honor the requested
            // count rather than forcing it to 0.
            await removeAllOwnedReminders()
            await setBadge(badgeCount)
            return
        }

        switch await center.authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                break
            case .notDetermined, .denied:
                Self.logger.authorizationNotGranted()
                await removeAllOwnedReminders()
                await setBadge(0)
                return
            @unknown default:
                Self.logger.authorizationUnknown()
                await removeAllOwnedReminders()
                await setBadge(0)
                return
        }

        let desiredIDs = Dictionary(
            scheduleDays.filter(\.hasWork).map { (identifier(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first },
        )

        // Cancel reminders we own that are no longer wanted (the day got logged
        // or fell out of the window).
        let pending = await center.pendingNotificationRequests()
        let pendingByID = Dictionary(
            pending.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let pendingIDs = Set(pendingByID.keys)
        let stalePending = pendingIDs.filter { isOwned($0) && desiredIDs[$0] == nil }
        let pendingWithWrongTime = desiredIDs.keys.filter { id in
            guard let request = pendingByID[id] else { return false }
            return !matchesReminderTime(request, reminderTime)
                || request.content.body != desiredIDs[id]?.body
                || request.content.title != String(localized: .reminderNotificationTitle)
        }
        let pendingToRemove = Set(stalePending).union(pendingWithWrongTime)
        if !pendingToRemove.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: Array(pendingToRemove))
        }

        let deliveredIDs = await center.deliveredNotificationIdentifiers()
        let staleDelivered = deliveredIDs.filter { isOwned($0) && desiredIDs[$0] == nil }
        if !staleDelivered.isEmpty {
            await center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
        }

        // Schedule new reminders, and replace existing requests whose trigger
        // time or content no longer matches the current assessment.
        let toSchedule = desiredIDs.filter { id, _ in
            !pendingIDs.contains(id) || pendingToRemove.contains(id)
        }
        for (id, reminder) in toSchedule {
            await scheduleReminder(identifier: id, reminder: reminder, time: reminderTime)
        }

        await setBadge(badgeCount)
        // Only log when the reconcile actually changed the schedule — it runs on
        // every launch/foreground and after every user write, so a no-op
        // reconcile (the common case) stays quiet.
        if !pendingToRemove.isEmpty || !staleDelivered.isEmpty || !toSchedule.isEmpty {
            Self.logger.reconciled(
                scheduled: .shared(.count, toSchedule.count),
                removed: .shared(.count, pendingToRemove.count),
                badge: .shared(.count, badgeCount),
            )
        }
    }

    private func scheduleReminder(
        identifier: String,
        reminder: EveningReminder,
        time: ReminderTime,
    ) async {
        let components = DateComponents(
            year: reminder.day.year,
            month: reminder.day.month,
            day: reminder.day.day,
            hour: time.hour,
            minute: time.minute,
        )

        let content = UNMutableNotificationContent()
        content.title = String(localized: .reminderNotificationTitle)
        content.body = reminder.body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger,
        )
        do {
            try await center.add(request)
        } catch {
            Self.logger.scheduleFailed(
                identifier: .restricted(.identifier, identifier),
                error: .restricted(.errorDetails, error),
            )
        }
    }

    private func matchesReminderTime(
        _ request: UNNotificationRequest,
        _ time: ReminderTime,
    ) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            return false
        }
        return trigger.dateComponents.hour == time.hour
            && trigger.dateComponents.minute == time.minute
    }

    private func removeAllOwnedReminders() async {
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter(isOwned)
        if !pendingIDs.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }
        let deliveredIDs = await center.deliveredNotificationIdentifiers()
        let ownedDeliveredIDs = deliveredIDs.filter(isOwned)
        if !ownedDeliveredIDs.isEmpty {
            await center.removeDeliveredNotifications(withIdentifiers: ownedDeliveredIDs)
        }
    }

    private func setBadge(_ count: Int) async {
        do {
            try await center.setBadgeCount(max(0, count))
        } catch {
            Self.logger.badgeUpdateFailed(
                error: .restricted(.errorDetails, error),
            )
        }
    }

    private func identifier(for day: CalendarDay) -> String {
        "\(Self.identifierPrefix).\(day.iso8601)"
    }

    private func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(Self.identifierPrefix) || identifier == "com.stuff.where.data-issues"
    }
}

protocol NotificationReminderCenter {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func deliveredNotificationIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
    func setBadgeCount(_ count: Int) async throws
}

/// Internal so the daily-summary scheduler in this module can share the same
/// `UNUserNotificationCenter` bridge rather than duplicating it.
final class UNUserNotificationCenterAdapter: NotificationReminderCenter,
    @unchecked Sendable
{
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        let delivered = await center.deliveredNotifications()
        return delivered.map(\.request.identifier)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func setBadgeCount(_ count: Int) async throws {
        try await center.setBadgeCount(count)
    }
}
