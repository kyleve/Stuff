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

/// Schedules the per-day local notifications and app-icon badge that nudge the
/// user to log a day before it ends. Behind a protocol so `ReminderReconciler`
/// can drive it deterministically from tests.
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
    ///   - badgeCount: the app-icon badge value the caller computed (unlogged-day
    ///     backlog plus any decoupled data-issue count). Set verbatim whether or
    ///     not `enabled`, so a caller that turns reminders off can still surface
    ///     an issue count; pass 0 to clear.
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

/// A `LoggingReminderScheduling` that does nothing. For SwiftUI previews,
/// view-model tests, and demo mode — anything that needs a reconciler without
/// touching `UNUserNotificationCenter`.
///
/// - Parameter authorized: what it reports back. Defaults to *un*authorized, so
///   the UI's "denied" affordances stay exercisable in previews and tests. Demo
///   mode passes `true`: it presents a fully-granted user (as its location
///   source does), and a scheduler claiming denial there would both log a
///   spurious warning and offer a dead-end trip to the Settings app.
public struct NoopLoggingReminderScheduler: LoggingReminderScheduling {
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

    public func reconcile(
        badgeCount _: Int,
        scheduleDays _: [Date],
        reminderTime _: ReminderTime,
        enabled _: Bool,
    ) async {}
}

/// Production `LoggingReminderScheduling` backed by `UNUserNotificationCenter`.
/// Only touches notification requests it owns (matched by identifier prefix) so
/// it never disturbs notifications from elsewhere in the app.
public final class UserNotificationReminderScheduler: LoggingReminderScheduling,
    @unchecked Sendable
{
    private let center: any NotificationReminderCenter
    private let calendar: Calendar

    private static let identifierPrefix = "com.stuff.where.logging-reminder"
    private static let logger = WhereLog.reminders(LoggingReminderSchedulerLog.self)

    public init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            return cal
        }(),
    ) {
        self.center = UNUserNotificationCenterAdapter(center: center)
        self.calendar = calendar
    }

    init(
        notificationCenter: any NotificationReminderCenter,
        calendar: Calendar,
    ) {
        center = notificationCenter
        self.calendar = calendar
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.logger { .authorizationRequestFailed(description: error.localizedDescription) }
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

    public func reconcile(
        badgeCount: Int,
        scheduleDays: [Date],
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
                Self.logger { .authorizationNotGranted }
                await removeAllOwnedReminders()
                await setBadge(0)
                return
            @unknown default:
                Self.logger { .authorizationUnknown }
                await removeAllOwnedReminders()
                await setBadge(0)
                return
        }

        let desiredIDs = Dictionary(
            scheduleDays.map { (identifier(for: $0), $0) },
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
        // time no longer matches the user's setting.
        let toSchedule = desiredIDs.filter { id, _ in
            !pendingIDs.contains(id) || pendingToRemove.contains(id)
        }
        for (id, day) in toSchedule {
            await scheduleReminder(identifier: id, day: day, time: reminderTime)
        }

        await setBadge(badgeCount)
        // Only log when the reconcile actually changed the schedule — it runs on
        // every launch/foreground and after every user write, so a no-op
        // reconcile (the common case) stays quiet.
        if !pendingToRemove.isEmpty || !staleDelivered.isEmpty || !toSchedule.isEmpty {
            Self.logger {
                .reconciled(
                    scheduled: toSchedule.count,
                    removed: pendingToRemove.count,
                    badge: badgeCount,
                )
            }
        }
    }

    private func scheduleReminder(identifier: String, day: Date, time: ReminderTime) async {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute

        let content = UNMutableNotificationContent()
        content.title = String(localized: .reminderNotificationTitle)
        content.body = String(localized: .reminderNotificationBody)
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
            Self.logger(attachments: [.error(error, name: "schedule-error")]) {
                .scheduleFailed(identifier: identifier, description: error.localizedDescription)
            }
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
            Self.logger { .badgeUpdateFailed(description: error.localizedDescription) }
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
