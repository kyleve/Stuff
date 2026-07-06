import Foundation
import LogKit
import Observation
import WhereCore

/// View-scoped model for the Settings reminder + daily-summary section: the
/// enable toggles, the time pickers, and whether notifications are authorized.
/// Owned as `@State` by `SettingsView`, so it's created when the Settings tab is
/// first shown and torn down with it.
///
/// This is the *editing* surface. The launch-time / foreground *application* of
/// the same schedules (reading `WherePreferences` and pushing to the reconcilers)
/// stays on the always-on `WhereSession` coordinator, since it must run whether
/// or not Settings is on screen. Both write through the shared `WherePreferences`
/// (the single source of truth): an edit here persists and reconciles the
/// scheduler live; the coordinator re-applies the persisted intent every launch
/// and foreground.
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
            Task { await applyReminderConfiguration() }
        }
    }

    /// Time of day the daily reminder fires. Persists and reconciles on change.
    public var reminderTime: ReminderTime {
        get { reminderTimeStorage }
        set {
            guard newValue != reminderTimeStorage else { return }
            reminderTimeStorage = newValue
            preferences.reminderTime = newValue
            Task { await applyReminderConfiguration() }
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
            Task { await applySummaryConfiguration() }
        }
    }

    /// Time of day the daily summary fires. Persists and reconciles on change.
    public var summaryTime: ReminderTime {
        get { summaryTimeStorage }
        set {
            guard newValue != summaryTimeStorage else { return }
            summaryTimeStorage = newValue
            preferences.summaryTime = newValue
            Task { await applySummaryConfiguration() }
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

    private let services: WhereServices
    private let preferences: WherePreferences
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private static let logger = WhereLog.channel(.session)

    public init(
        services: WhereServices,
        preferences: WherePreferences,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.services = services
        self.preferences = preferences
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        remindersEnabledStorage = preferences.remindersEnabled
        reminderTimeStorage = preferences.reminderTime
        summaryEnabledStorage = preferences.summaryEnabled
        summaryTimeStorage = preferences.summaryTime
    }

    /// Refresh whether the system has granted notification permission. Called
    /// when Settings appears, in case the user changed it in the Settings app.
    public func refreshNotificationAuthorization() async {
        notificationsAuthorized = await services.reminders.isAuthorized()
    }

    private func applyReminderConfiguration() async {
        await services.reminders.configure(enabled: remindersEnabled, time: reminderTime)
        await refreshNotificationAuthorization()
    }

    private func applySummaryConfiguration() async {
        await services.summary.configure(enabled: summaryEnabled, time: summaryTime)
        await refreshNotificationAuthorization()
    }
}
