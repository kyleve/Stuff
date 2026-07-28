import Foundation
import PeriscopeCore
import UserNotifications

/// Schedules the single repeating local notification that gives the user a
/// daily recap of where they've been this year. Behind a protocol so
/// `DailySummaryReconciler` can drive it deterministically from tests.
public protocol DailySummaryScheduling: Sendable {
    /// Ask the system for permission to post alerts/sounds. Returns whether the
    /// app is authorized afterward. Safe to call repeatedly.
    func requestAuthorization() async -> Bool

    /// Whether the app is currently authorized to post notifications, so the UI
    /// can route the user to Settings when they've enabled the summary but
    /// denied the system permission.
    func isAuthorized() async -> Bool

    /// Reconcile the scheduled summary notification against the current intent.
    ///
    /// - Parameters:
    ///   - enabled: master switch. When `false`, the owned summary notification
    ///     is cancelled.
    ///   - time: time of day the summary fires.
    ///   - body: the recap text to show. Recomputed by the controller from the
    ///     latest year-to-date totals; when it changes the pending request is
    ///     replaced so the next delivery reflects current data.
    func reconcile(enabled: Bool, time: ReminderTime, body: String) async
}

/// A `DailySummaryScheduling` that does nothing. For SwiftUI previews,
/// view-model tests, and demo mode — anything that needs a reconciler without
/// touching `UNUserNotificationCenter`.
///
/// - Parameter authorized: what it reports back. Defaults to *un*authorized, so
///   the UI's "denied" affordances stay exercisable in previews and tests. Demo
///   mode passes `true`, presenting a fully-granted user; claiming denial there
///   would log a spurious warning and offer a dead-end trip to Settings.
public struct NoopDailySummaryScheduler: DailySummaryScheduling {
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

    public func reconcile(enabled _: Bool, time _: ReminderTime, body _: String) async {}
}

/// Production `DailySummaryScheduling` backed by `UNUserNotificationCenter`.
/// Schedules one repeating daily notification under a dedicated identifier, so
/// it never disturbs the logging reminders (which own a different prefix) or
/// anything else in the app.
public final class UserNotificationDailySummaryScheduler: DailySummaryScheduling,
    @unchecked Sendable
{
    private let center: any NotificationReminderCenter

    /// One repeating notification, so a single stable identifier is enough.
    private static let identifier = "com.stuff.where.daily-summary"
    private static let logger = WhereLog.reminders(DailySummarySchedulerLog.self)

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

    public func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
        guard enabled else {
            await removeAllOwned()
            return
        }

        switch await center.authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                break
            case .notDetermined, .denied:
                Self.logger { .authorizationNotGranted }
                await removeAllOwned()
                return
            @unknown default:
                Self.logger { .authorizationUnknown }
                await removeAllOwned()
                return
        }

        let owned = await center.pendingNotificationRequests().filter { isOwned($0.identifier) }
        // Leave a correct request in place so we don't churn the schedule on
        // every reconcile; only the first owned request can ever be the right
        // one, so a stray duplicate forces a rebuild.
        if owned.count == 1,
           let existing = owned.first,
           matchesTime(existing, time),
           existing.content.body == body
        {
            return
        }

        let ownedIDs = owned.map(\.identifier)
        if !ownedIDs.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: ownedIDs)
        }
        await scheduleSummary(time: time, body: body)
    }

    private func scheduleSummary(time: ReminderTime, body: String) async {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        let content = UNMutableNotificationContent()
        content.title = String(localized: .summaryNotificationTitle)
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: trigger,
        )
        do {
            try await center.add(request)
            Self.logger {
                .scheduled(time: String(format: "%02d:%02d", time.hour, time.minute))
            }
        } catch {
            Self.logger(attachments: [.error(error, name: "schedule-error")]) {
                .scheduleFailed(description: error.localizedDescription)
            }
        }
    }

    private func matchesTime(_ request: UNNotificationRequest, _ time: ReminderTime) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            return false
        }
        return trigger.dateComponents.hour == time.hour
            && trigger.dateComponents.minute == time.minute
    }

    private func removeAllOwned() async {
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(isOwned)
        if !pendingIDs.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }
        let deliveredIDs = await center.deliveredNotificationIdentifiers().filter(isOwned)
        if !deliveredIDs.isEmpty {
            await center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    private func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(Self.identifier)
    }
}
