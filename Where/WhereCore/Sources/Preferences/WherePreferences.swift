import Foundation
import RegionKit

/// The app's persisted user intent — onboarding completion, background-tracking
/// intent, forecast visibility, and the reminder / daily-summary schedules —
/// plus small pieces of UI continuity state, behind a `KeyValueStore` so
/// production uses `UserDefaults` and tests use an in-memory double.
///
/// `store` is deliberately not defaulted: defaulting it to
/// `UserDefaults.standard` made the real, process-wide defaults the thing you
/// got by *saying nothing*, so a test or preview that omitted it silently read
/// and wrote the host's own settings — leaking state between tests and across
/// runs. Production names `UserDefaults.standard`; everything else names
/// `InMemoryKeyValueStore()`.
///
/// Owns the defaults keys and the `reset()` that returns them to first-install
/// state, so that teardown lives in Core rather than the UI layer. Values are
/// read/written eagerly; callers that need observation (SwiftUI) mirror them in
/// their own observable state.
public final class WherePreferences {
    private let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    /// Whether first-run onboarding has been completed. Defaults to `false` so
    /// onboarding shows on a fresh install.
    public var hasOnboarded: Bool {
        get { store.bool(forKey: Keys.hasOnboarded.rawValue) }
        set { store.set(newValue, forKey: Keys.hasOnboarded.rawValue) }
    }

    /// Persisted intent to track in the background. Defaults to `true` so that,
    /// once the user grants Always, tracking resumes automatically every launch.
    public var wantsTracking: Bool {
        get { store.object(forKey: Keys.wantsTracking.rawValue) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.wantsTracking.rawValue) }
    }

    /// Whether the annual-estimate summary appears on the Locations tab.
    /// Defaults to `true` so an existing or fresh install sees the feature until
    /// the user explicitly turns it off.
    public var showsLocationForecastsOnLocationsTab: Bool {
        get {
            store.object(forKey: Keys.showsLocationForecastsOnLocationsTab.rawValue) as? Bool
                ?? true
        }
        set { store.set(newValue, forKey: Keys.showsLocationForecastsOnLocationsTab.rawValue) }
    }

    /// Whether the daily "log before the day ends" reminder is enabled. Defaults
    /// to `true` so the safety net is active out of the box.
    public var remindersEnabled: Bool {
        get { store.object(forKey: Keys.remindersEnabled.rawValue) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.remindersEnabled.rawValue) }
    }

    /// Time of day the daily reminder fires.
    public var reminderTime: ReminderTime {
        get {
            ReminderTime(
                hour: store.object(forKey: Keys.reminderHour.rawValue) as? Int
                    ?? ReminderTime.defaultEvening.hour,
                minute: store.object(forKey: Keys.reminderMinute.rawValue) as? Int
                    ?? ReminderTime.defaultEvening.minute,
            )
        }
        set {
            store.set(newValue.hour, forKey: Keys.reminderHour.rawValue)
            store.set(newValue.minute, forKey: Keys.reminderMinute.rawValue)
        }
    }

    /// Whether the daily summary recap notification is enabled. Defaults to
    /// `true` so the year-to-date recap arrives out of the box.
    public var summaryEnabled: Bool {
        get { store.object(forKey: Keys.summaryEnabled.rawValue) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.summaryEnabled.rawValue) }
    }

    /// Time of day the daily summary fires.
    public var summaryTime: ReminderTime {
        get {
            ReminderTime(
                hour: store.object(forKey: Keys.summaryHour.rawValue) as? Int
                    ?? ReminderTime.defaultMorning.hour,
                minute: store.object(forKey: Keys.summaryMinute.rawValue) as? Int
                    ?? ReminderTime.defaultMorning.minute,
            )
        }
        set {
            store.set(newValue.hour, forKey: Keys.summaryHour.rawValue)
            store.set(newValue.minute, forKey: Keys.summaryMinute.rawValue)
        }
    }

    /// Whether the "you have issues to resolve" notification is enabled, and
    /// whether the unresolved-issue count contributes to the app-icon badge.
    /// Defaults to `true` so the nudge and badge are active out of the box.
    public var issueAlertsEnabled: Bool {
        get { store.object(forKey: Keys.issueAlertsEnabled.rawValue) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.issueAlertsEnabled.rawValue) }
    }

    /// GPS border-drift detection threshold in meters. Defaults to 10 km.
    public var driftThresholdMeters: Int {
        get {
            store.object(forKey: Keys.driftThresholdMeters.rawValue) as? Int
                ?? DriftThreshold.default.rawValue
        }
        set { store.set(newValue, forKey: Keys.driftThresholdMeters.rawValue) }
    }

    /// The primary Location-card counts last presented for `year`, or `nil`
    /// when that year has no baseline yet. This is non-authoritative UI
    /// continuity state: the current report remains the source of truth.
    public func lastSeenLocationDayCounts(in year: Int) -> [Region: Int]? {
        guard
            let snapshots = store.object(forKey: Keys.lastSeenLocationDayCounts.rawValue)
            as? [String: [String: Int]],
            let rawCounts = snapshots[String(year)]
        else {
            return nil
        }

        return rawCounts.reduce(into: [:]) { counts, entry in
            guard let region = Region(rawValue: entry.key) else { return }
            counts[region] = entry.value
        }
    }

    /// Replaces the primary Location-card baseline for `year`, retaining the
    /// other years the user has viewed.
    public func setLastSeenLocationDayCounts(_ counts: [Region: Int], in year: Int) {
        var snapshots = store.object(forKey: Keys.lastSeenLocationDayCounts.rawValue)
            as? [String: [String: Int]] ?? [:]
        snapshots[String(year)] = Dictionary(uniqueKeysWithValues: counts.map { region, days in
            (region.rawValue, days)
        })
        store.set(snapshots, forKey: Keys.lastSeenLocationDayCounts.rawValue)
    }

    /// Clear every persisted preference so the next launch behaves like a fresh
    /// install: onboarding shows again, background tracking returns to its
    /// default intent, reminder/summary schedules revert to defaults, and UI
    /// continuity snapshots are forgotten.
    /// Removing the keys (rather than writing `false`/`0`) lets the
    /// default-valued getters report first-install state again.
    public func reset() {
        for key in Keys.allCases {
            store.removeObject(forKey: key.rawValue)
        }
    }

    /// String-backed so each case *is* its defaults key, and `CaseIterable` so
    /// `reset()` clears every key without a hand-maintained `all` list to keep in
    /// sync — adding a case is all it takes to have it reset.
    private enum Keys: String, CaseIterable {
        case hasOnboarded = "where.hasOnboarded"
        case wantsTracking = "where.wantsBackgroundTracking"
        case showsLocationForecastsOnLocationsTab = "where.showsLocationForecastsOnLocationsTab"
        case remindersEnabled = "where.remindersEnabled"
        case reminderHour = "where.reminderHour"
        case reminderMinute = "where.reminderMinute"
        case summaryEnabled = "where.summaryEnabled"
        case summaryHour = "where.summaryHour"
        case summaryMinute = "where.summaryMinute"
        case issueAlertsEnabled = "where.issueAlertsEnabled"
        case driftThresholdMeters = "where.driftThresholdMeters"
        case lastSeenLocationDayCounts = "where.lastSeenLocationDayCounts"
    }
}
