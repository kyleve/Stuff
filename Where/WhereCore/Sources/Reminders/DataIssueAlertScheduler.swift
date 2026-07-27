import Foundation
import PeriscopeCore
import UserNotifications

/// Schedules the single local notification that nudges the user to open the
/// Resolve tab when there are unresolved data-quality issues. Behind a protocol
/// so `DataIssueAlertReconciler` can drive it deterministically from tests.
public protocol DataIssueAlertScheduling: Sendable {
    /// Ask the system for permission to post alerts/sounds. Returns whether the
    /// app is authorized afterward. Safe to call repeatedly.
    func requestAuthorization() async -> Bool

    /// Whether the app is currently authorized to post notifications, so the UI
    /// can route the user to Settings when they've enabled issue alerts but
    /// denied the system permission.
    func isAuthorized() async -> Bool

    /// Reconcile the scheduled issue-alert notification against the current
    /// intent.
    ///
    /// - Parameters:
    ///   - enabled: master switch — the user's `issueAlertsEnabled` intent AND
    ///     there being at least one unresolved issue. When `false`, the owned
    ///     notification is cancelled (so resolving the last issue clears it).
    ///   - time: time of day the alert fires.
    ///   - body: the alert text to show, recomputed by the controller from the
    ///     current issue count; when it changes the pending request is replaced
    ///     so the next delivery reflects the current count.
    func reconcile(enabled: Bool, time: ReminderTime, body: String) async
}

#if DEBUG
    /// A `DataIssueAlertScheduling` that does nothing, for view-model tests that
    /// need a controller without touching `UNUserNotificationCenter`. Reports
    /// unauthorized so the UI's "denied" affordances stay exercisable.
    ///
    /// `@_spi(Testing)` + `#if DEBUG` per the agents.md testing-hook convention:
    /// it's test-only scaffolding that mustn't ship in release. Import it with
    /// `@_spi(Testing) import WhereCore` (add `@testable` in WhereCore's own
    /// tests) and inject it via `WhereServices(issueAlertScheduler:)`.
    @_spi(Testing)
    public struct NoopDataIssueAlertScheduler: DataIssueAlertScheduling {
        public init() {}

        public func requestAuthorization() async -> Bool {
            false
        }

        public func isAuthorized() async -> Bool {
            false
        }

        public func reconcile(enabled _: Bool, time _: ReminderTime, body _: String) async {}
    }
#endif

/// Production `DataIssueAlertScheduling` backed by `UNUserNotificationCenter`.
/// Schedules one repeating daily notification under a dedicated identifier, so
/// it never disturbs the logging reminders or the daily summary (which own
/// different prefixes) or anything else in the app.
public final class UserNotificationDataIssueAlertScheduler: DataIssueAlertScheduling,
    @unchecked Sendable
{
    private let center: any NotificationReminderCenter

    /// One repeating notification, so a single stable identifier is enough.
    private static let identifier = "com.stuff.where.data-issues"
    private static let logger = WhereLog.reminders(DataIssueAlertSchedulerLog.self)

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

    /// Bring the owned pending request in line with the intent (see the protocol
    /// requirement for the parameter contract): clear it when disabled or when
    /// notifications aren't authorized; otherwise leave an already-correct
    /// request untouched and only (re)build it when the fire time or body changed
    /// — or a stray duplicate crept in — so a steady state doesn't churn the
    /// schedule.
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
        await scheduleAlert(time: time, body: body)
    }

    private func scheduleAlert(time: ReminderTime, body: String) async {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        let content = UNMutableNotificationContent()
        content.title = String(localized: .dataIssuesNotificationTitle)
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
