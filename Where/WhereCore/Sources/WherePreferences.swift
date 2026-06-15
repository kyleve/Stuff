import Foundation

/// The app's persisted user intent — onboarding completion, background-tracking
/// intent, and the reminder / daily-summary schedules — behind a `KeyValueStore`
/// so production uses `UserDefaults` and tests use an in-memory double.
///
/// Owns the defaults keys and the `reset()` that returns them to first-install
/// state, so that teardown lives in Core rather than the UI layer. Values are
/// read/written eagerly; callers that need observation (SwiftUI) mirror them in
/// their own observable state.
public final class WherePreferences {
    private let store: any KeyValueStore

    public init(store: any KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// Whether first-run onboarding has been completed. Defaults to `false` so
    /// onboarding shows on a fresh install.
    public var hasOnboarded: Bool {
        get { store.bool(forKey: Keys.hasOnboarded) }
        set { store.set(newValue, forKey: Keys.hasOnboarded) }
    }

    /// Persisted intent to track in the background. Defaults to `true` so that,
    /// once the user grants Always, tracking resumes automatically every launch.
    public var wantsTracking: Bool {
        get { store.object(forKey: Keys.wantsTracking) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.wantsTracking) }
    }

    /// Whether the daily "log before the day ends" reminder is enabled. Defaults
    /// to `true` so the safety net is active out of the box.
    public var remindersEnabled: Bool {
        get { store.object(forKey: Keys.remindersEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.remindersEnabled) }
    }

    /// Time of day the daily reminder fires.
    public var reminderTime: ReminderTime {
        get {
            ReminderTime(
                hour: store.object(forKey: Keys.reminderHour) as? Int
                    ?? ReminderTime.defaultEvening.hour,
                minute: store.object(forKey: Keys.reminderMinute) as? Int
                    ?? ReminderTime.defaultEvening.minute,
            )
        }
        set {
            store.set(newValue.hour, forKey: Keys.reminderHour)
            store.set(newValue.minute, forKey: Keys.reminderMinute)
        }
    }

    /// Whether the daily summary recap notification is enabled. Defaults to
    /// `true` so the year-to-date recap arrives out of the box.
    public var summaryEnabled: Bool {
        get { store.object(forKey: Keys.summaryEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.summaryEnabled) }
    }

    /// Time of day the daily summary fires.
    public var summaryTime: ReminderTime {
        get {
            ReminderTime(
                hour: store.object(forKey: Keys.summaryHour) as? Int
                    ?? ReminderTime.defaultMorning.hour,
                minute: store.object(forKey: Keys.summaryMinute) as? Int
                    ?? ReminderTime.defaultMorning.minute,
            )
        }
        set {
            store.set(newValue.hour, forKey: Keys.summaryHour)
            store.set(newValue.minute, forKey: Keys.summaryMinute)
        }
    }

    /// Clear every persisted preference so the next launch behaves like a fresh
    /// install: onboarding shows again, background tracking returns to its
    /// default intent, and the reminder/summary schedules revert to defaults.
    /// Removing the keys (rather than writing `false`/`0`) lets the
    /// default-valued getters report first-install state again.
    public func reset() {
        for key in Keys.all {
            store.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let hasOnboarded = "where.hasOnboarded"
        static let wantsTracking = "where.wantsBackgroundTracking"
        static let remindersEnabled = "where.remindersEnabled"
        static let reminderHour = "where.reminderHour"
        static let reminderMinute = "where.reminderMinute"
        static let summaryEnabled = "where.summaryEnabled"
        static let summaryHour = "where.summaryHour"
        static let summaryMinute = "where.summaryMinute"

        static let all = [
            hasOnboarded,
            wantsTracking,
            remindersEnabled,
            reminderHour,
            reminderMinute,
            summaryEnabled,
            summaryHour,
            summaryMinute,
        ]
    }
}
