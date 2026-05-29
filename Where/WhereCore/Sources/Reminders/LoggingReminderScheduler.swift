import Foundation
import os
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
}

/// Schedules the per-day local notifications and app-icon badge that nudge the
/// user to log a day before it ends. Behind a protocol so `WhereController` can
/// drive it deterministically from tests.
public protocol LoggingReminderScheduling: Sendable {
    /// Ask the system for permission to post alerts/sounds/badges. Returns
    /// whether the app is authorized afterward. Safe to call repeatedly.
    func requestAuthorization() async -> Bool

    /// Whether the app is currently authorized to post notifications and set
    /// the badge. Lets the UI route the user to Settings when they've enabled
    /// reminders but denied the system permission.
    func isAuthorized() async -> Bool

    /// Reconcile scheduled reminders and the app-icon badge against the current
    /// picture.
    ///
    /// - Parameters:
    ///   - badgeCount: total unlogged days this year (the backlog). Shown as the
    ///     app-icon badge when `enabled`, cleared to 0 otherwise.
    ///   - scheduleDays: upcoming days (today + a small buffer) that are still
    ///     unlogged and should each get a reminder at `reminderTime`. A day that
    ///     drops out of this set (because it got logged) has its pending and
    ///     delivered reminder removed — this is the "recorded successfully,
    ///     remove the notification" path.
    ///   - reminderTime: time of day each reminder fires.
    ///   - enabled: master switch. When `false`, every reminder this app
    ///     scheduled is cancelled and the badge cleared.
    func reconcile(
        badgeCount: Int,
        scheduleDays: [Date],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async
}

/// Production `LoggingReminderScheduling` backed by `UNUserNotificationCenter`.
/// Only touches notification requests it owns (matched by identifier prefix) so
/// it never disturbs notifications from elsewhere in the app.
public final class UserNotificationReminderScheduler: LoggingReminderScheduling,
    @unchecked Sendable
{
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    private static let identifierPrefix = "com.stuff.where.logging-reminder"
    private static let logger = Logger(
        subsystem: "com.stuff.where",
        category: "LoggingReminderScheduler",
    )

    public init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            return cal
        }(),
    ) {
        self.center = center
        self.calendar = calendar
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.logger.error(
                "Notification authorization request failed: \(error.localizedDescription, privacy: .public)",
            )
            return false
        }
    }

    public func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            default:
                return false
        }
    }

    public func reconcile(
        badgeCount: Int,
        scheduleDays: [Date],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        guard enabled else {
            await removeAllOwnedReminders()
            await setBadge(0)
            return
        }

        // Without authorization we can neither post alerts nor set the badge,
        // so there's nothing useful to reconcile.
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return
        }

        let desiredIDs = Dictionary(
            scheduleDays.map { (identifier(for: $0), $0) },
            uniquingKeysWith: { first, _ in first },
        )

        // Cancel reminders we own that are no longer wanted (the day got logged
        // or fell out of the window).
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let stalePending = pendingIDs.filter { isOwned($0) && desiredIDs[$0] == nil }
        if !stalePending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stalePending))
        }

        let delivered = await center.deliveredNotifications()
        let staleDelivered = delivered
            .map(\.request.identifier)
            .filter { isOwned($0) && desiredIDs[$0] == nil }
        if !staleDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
        }

        // Schedule the wanted reminders that aren't already pending.
        for (id, day) in desiredIDs where !pendingIDs.contains(id) {
            await scheduleReminder(identifier: id, day: day, time: reminderTime)
        }

        await setBadge(badgeCount)
    }

    private func scheduleReminder(identifier: String, day: Date, time: ReminderTime) async {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute

        let content = UNMutableNotificationContent()
        content.title = String(localized: "reminder.notification.title", bundle: .module)
        content.body = String(localized: "reminder.notification.body", bundle: .module)
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
            Self.logger.error(
                "Failed to schedule reminder \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)",
            )
        }
    }

    private func removeAllOwnedReminders() async {
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter(isOwned)
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.map(\.request.identifier).filter(isOwned)
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    private func setBadge(_ count: Int) async {
        do {
            try await center.setBadgeCount(max(0, count))
        } catch {
            Self.logger.error(
                "Failed to set badge count: \(error.localizedDescription, privacy: .public)",
            )
        }
    }

    private func identifier(for day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let dayOfMonth = components.day ?? 0
        return "\(Self.identifierPrefix).\(year)-\(month)-\(dayOfMonth)"
    }

    private func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(Self.identifierPrefix)
    }
}
