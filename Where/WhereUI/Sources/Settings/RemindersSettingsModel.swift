import BroadwayCore
import Foundation
import Observation
import WhereCore

/// The Alerts destination owns this editing state. Accepted preference changes
/// reconcile through the session even when the destination closes.
@MainActor
@Observable
public final class RemindersSettingsModel {
    /// Whether the daily "log before the day ends" reminder is enabled. Persists
    /// across launches; the setter persists the intent and reconciles the
    /// schedule.
    public var remindersEnabled: Bool {
        get { remindersEnabledStorage }
        set {
            guard newValue != remindersEnabledStorage else { return }
            remindersEnabledStorage = newValue
            preferences.remindersEnabled = newValue
            session.enqueueNotificationConfiguration(.reminder)
        }
    }

    /// Time of day the daily reminder fires. Persists and reconciles on change.
    public var reminderTime: ReminderTime {
        get { reminderTimeStorage }
        set {
            guard newValue != reminderTimeStorage else { return }
            reminderTimeStorage = newValue
            preferences.reminderTime = newValue
            session.enqueueNotificationConfiguration(.reminder)
        }
    }

    /// `Date`-typed projection of `reminderTime` for the Settings `DatePicker`,
    /// which works in `Date`. Lets the view bind `$reminders.reminderTimeOfDay`
    /// directly; writes round-trip back into `reminderTime`.
    public var reminderTimeOfDay: Date {
        get {
            calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: now(),
            ) ?? now()
        }
        set {
            let components = calendar.dateComponents([.hour, .minute], from: newValue)
            reminderTime = ReminderTime(
                hour: components.hour ?? ReminderTime.defaultEvening.hour,
                minute: components.minute ?? ReminderTime.defaultEvening.minute,
            )
        }
    }

    /// Whether the daily summary recap notification is enabled. Persists across
    /// launches; the setter persists the intent and reconciles the summary.
    public var summaryEnabled: Bool {
        get { summaryEnabledStorage }
        set {
            guard newValue != summaryEnabledStorage else { return }
            summaryEnabledStorage = newValue
            preferences.summaryEnabled = newValue
            session.enqueueNotificationConfiguration(.summary)
        }
    }

    /// Time of day the daily summary fires. Persists and reconciles on change.
    public var summaryTime: ReminderTime {
        get { summaryTimeStorage }
        set {
            guard newValue != summaryTimeStorage else { return }
            summaryTimeStorage = newValue
            preferences.summaryTime = newValue
            session.enqueueNotificationConfiguration(.summary)
        }
    }

    /// `Date`-typed projection of `summaryTime`, mirroring `reminderTimeOfDay`.
    public var summaryTimeOfDay: Date {
        get {
            calendar.date(
                bySettingHour: summaryTime.hour,
                minute: summaryTime.minute,
                second: 0,
                of: now(),
            ) ?? now()
        }
        set {
            let components = calendar.dateComponents([.hour, .minute], from: newValue)
            summaryTime = ReminderTime(
                hour: components.hour ?? ReminderTime.defaultMorning.hour,
                minute: components.minute ?? ReminderTime.defaultMorning.minute,
            )
        }
    }

    /// Whether the "you have issues to resolve" notification is enabled (and the
    /// unresolved-issue count contributes to the app-icon badge). Persists across
    /// launches; the setter persists the intent and reconciles both the alert and
    /// the badge.
    public var issueAlertsEnabled: Bool {
        get { issueAlertsEnabledStorage }
        set {
            guard newValue != issueAlertsEnabledStorage else { return }
            issueAlertsEnabledStorage = newValue
            preferences.issueAlertsEnabled = newValue
            let alert = session.enqueueNotificationConfiguration(.issueAlert)
            // Set the badge after the issue alert's authorization request settles.
            session.enqueueNotificationConfiguration(.reminder, after: alert)
        }
    }

    /// Whether the system has granted notification permission. Lets the Settings
    /// UI route the user to the system Settings app when they've enabled
    /// reminders/summary but denied permission. Refreshed on appear and after
    /// each configuration apply.
    public private(set) var notificationsAuthorized = false

    /// Observed backing storage for the reminder toggle/time. The public computed
    /// properties layer persistence + reconciliation onto their setters, which a
    /// stored property can't express.
    private var remindersEnabledStorage: Bool
    private var reminderTimeStorage: ReminderTime
    /// Observed backing storage for the summary toggle/time, mirroring the
    /// reminder storage above.
    private var summaryEnabledStorage: Bool
    private var summaryTimeStorage: ReminderTime
    /// Observed backing storage for the issue-alert toggle.
    private var issueAlertsEnabledStorage: Bool

    private let session: WhereSession
    private let preferences: WherePreferences
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(session: WhereSession) {
        self.session = session
        let preferences = session.preferences
        self.preferences = preferences
        now = session.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        remindersEnabledStorage = preferences.remindersEnabled
        reminderTimeStorage = preferences.reminderTime
        summaryEnabledStorage = preferences.summaryEnabled
        summaryTimeStorage = preferences.summaryTime
        issueAlertsEnabledStorage = preferences.issueAlertsEnabled
    }

    var authorizationRefreshTrigger: EventTrigger {
        session.notificationConfigurationTrigger
    }

    /// Refresh upon entry and when the session finishes applying a choice.
    public func refreshNotificationAuthorization() async {
        let requestedRevision = authorizationRefreshTrigger
        let authorized = await session.services.reminders.isAuthorized()
        guard !Task.isCancelled, requestedRevision == authorizationRefreshTrigger else { return }
        notificationsAuthorized = authorized
    }
}
