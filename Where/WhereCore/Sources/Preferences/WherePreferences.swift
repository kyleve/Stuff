import Foundation
import RegionKit

/// The app's persisted user intent — onboarding completion, presentation
/// theme, Locations-card visibility, and notification schedules — plus small
/// pieces of UI continuity and acknowledgement state, behind a `KeyValueStore`
/// so production uses `UserDefaults` and tests use an in-memory double.
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
    private let invalidDiagnosticValue: (String) -> Void

    public init(store: any KeyValueStore) {
        self.store = store
        invalidDiagnosticValue = { message in assertionFailure(message) }
    }

    init(
        store: any KeyValueStore,
        invalidDiagnosticValue: @escaping (String) -> Void,
    ) {
        self.store = store
        self.invalidDiagnosticValue = invalidDiagnosticValue
    }

    /// Whether first-run onboarding has been completed. Defaults to `false` so
    /// onboarding shows on a fresh install.
    public var hasOnboarded: Bool {
        get { store.bool(forKey: Keys.hasOnboarded.rawValue) }
        set { store.set(newValue, forKey: Keys.hasOnboarded.rawValue) }
    }

    /// Whether Locations cards render recorded GPS fixes inside their region
    /// outlines. Defaults to `true` so the visualization is visible until the
    /// user explicitly turns it off.
    public var showsRecordedLocationDots: Bool {
        get { store.object(forKey: Keys.showsRecordedLocationDots.rawValue) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.showsRecordedLocationDots.rawValue) }
    }

    /// The device-local presentation theme. Missing and unrecognized values
    /// resolve to Standard so upgrades preserve the app's familiar appearance.
    public var theme: WhereTheme {
        get {
            guard
                let rawValue = store.object(forKey: Keys.theme.rawValue) as? String,
                let theme = WhereTheme(rawValue: rawValue)
            else {
                return .standard
            }
            return theme
        }
        set { store.set(newValue.rawValue, forKey: Keys.theme.rawValue) }
    }

    /// Whether annual estimates, stay planning, and their projections appear.
    /// Defaults to `true` so an existing or fresh install sees the feature until
    /// the user explicitly turns it off. The defaults key retains its original
    /// Locations-only name so an existing choice survives the broader meaning.
    public var showsEstimatedTimeAndPlanning: Bool {
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

    /// The user's saved, vendor-neutral diagnostic-reporting choices.
    public var diagnosticReportingConfiguration: DiagnosticReportingConfiguration {
        get { diagnosticReportingConfiguration(isDebugBuild: Self.isDebugBuild) }
        set { setDiagnosticReportingConfiguration(newValue) }
    }

    /// Resolves defaults for an explicit build flavor so both shipping and
    /// developer first-install behavior can be verified in one test process.
    public func diagnosticReportingConfiguration(
        isDebugBuild: Bool,
    ) -> DiagnosticReportingConfiguration {
        let defaults = DiagnosticReportingConfiguration.defaults(isDebugBuild: isDebugBuild)
        var hasInvalidValue = false
        let sharesCrashReports = diagnosticBool(
            forKey: .sharesCrashReports,
            defaultValue: defaults.sharesCrashReports,
            hasInvalidValue: &hasInvalidValue,
        )
        let sharesSessionReplays = diagnosticBool(
            forKey: .sharesSessionReplays,
            defaultValue: defaults.sharesSessionReplays,
            hasInvalidValue: &hasInvalidValue,
        )

        guard let storedLevel = store.object(forKey: Keys.remoteLogLevel.rawValue) else {
            return DiagnosticReportingConfiguration(
                sharesCrashReports: sharesCrashReports,
                sharesSessionReplays: sharesSessionReplays,
                remoteLogging: hasInvalidValue ? .off : defaults.remoteLogging,
            )
        }
        guard let rawLevel = storedLevel as? String else {
            invalidDiagnosticValue("Invalid persisted remote logging level type")
            return DiagnosticReportingConfiguration(
                sharesCrashReports: sharesCrashReports,
                sharesSessionReplays: sharesSessionReplays,
                remoteLogging: .off,
            )
        }
        guard rawLevel != "off" else {
            return DiagnosticReportingConfiguration(
                sharesCrashReports: sharesCrashReports,
                sharesSessionReplays: sharesSessionReplays,
                remoteLogging: .off,
            )
        }
        guard let minimumLevel = RemoteLogLevel(rawValue: rawLevel) else {
            invalidDiagnosticValue("Invalid persisted remote logging level: \(rawLevel)")
            return DiagnosticReportingConfiguration(
                sharesCrashReports: sharesCrashReports,
                sharesSessionReplays: sharesSessionReplays,
                remoteLogging: .off,
            )
        }

        let storedMetadataPolicy = store.object(forKey: Keys.remoteLogMetadataPolicy.rawValue)
        let rawMetadataPolicy: String
        if let storedMetadataPolicy {
            guard let value = storedMetadataPolicy as? String else {
                invalidDiagnosticValue("Invalid persisted remote metadata policy type")
                return DiagnosticReportingConfiguration(
                    sharesCrashReports: sharesCrashReports,
                    sharesSessionReplays: sharesSessionReplays,
                    remoteLogging: .off,
                )
            }
            rawMetadataPolicy = value
        } else {
            rawMetadataPolicy = RemoteLogMetadataPolicy.approvedFields.rawValue
        }
        guard let metadataPolicy = RemoteLogMetadataPolicy(rawValue: rawMetadataPolicy) else {
            invalidDiagnosticValue("Invalid persisted remote metadata policy: \(rawMetadataPolicy)")
            return DiagnosticReportingConfiguration(
                sharesCrashReports: sharesCrashReports,
                sharesSessionReplays: sharesSessionReplays,
                remoteLogging: .off,
            )
        }
        return DiagnosticReportingConfiguration(
            sharesCrashReports: sharesCrashReports,
            sharesSessionReplays: sharesSessionReplays,
            remoteLogging: hasInvalidValue ? .off : .enabled(
                minimumLevel: minimumLevel,
                metadataPolicy: metadataPolicy,
            ),
        )
    }

    private func diagnosticBool(
        forKey key: Keys,
        defaultValue: Bool,
        hasInvalidValue: inout Bool,
    ) -> Bool {
        guard let storedValue = store.object(forKey: key.rawValue) else { return defaultValue }
        guard let value = storedValue as? Bool else {
            hasInvalidValue = true
            invalidDiagnosticValue("Invalid persisted diagnostic Boolean: \(key.rawValue)")
            return defaultValue
        }
        return value
    }

    public func setDiagnosticReportingConfiguration(
        _ configuration: DiagnosticReportingConfiguration,
    ) {
        store.set(configuration.sharesCrashReports, forKey: Keys.sharesCrashReports.rawValue)
        store.set(configuration.sharesSessionReplays, forKey: Keys.sharesSessionReplays.rawValue)
        switch configuration.remoteLogging {
            case .off:
                store.set("off", forKey: Keys.remoteLogLevel.rawValue)
                store.removeObject(forKey: Keys.remoteLogMetadataPolicy.rawValue)
            case let .enabled(minimumLevel, metadataPolicy):
                store.set(minimumLevel.rawValue, forKey: Keys.remoteLogLevel.rawValue)
                store.set(metadataPolicy.rawValue, forKey: Keys.remoteLogMetadataPolicy.rawValue)
        }
    }

    /// Generation bookkeeping for the recording-configuration warning. This is UI continuity
    /// state: the live recording policy and authorization remain authoritative.
    public var recordingConfigurationWarningRegistration:
        RecordingConfigurationWarningRegistration
    {
        get {
            guard
                let data = store.object(
                    forKey: Keys.recordingConfigurationWarningRegistration.rawValue,
                ) as? Data
            else {
                return RecordingConfigurationWarningRegistration()
            }
            do {
                let registration = try JSONDecoder().decode(
                    RecordingConfigurationWarningRegistration.self,
                    from: data,
                )
                guard registration.isValid else {
                    assertionFailure("Decoded an invalid recording warning registration.")
                    return RecordingConfigurationWarningRegistration()
                }
                return registration
            } catch {
                assertionFailure("Could not decode recording warning registration: \(error)")
                return RecordingConfigurationWarningRegistration()
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                store.set(data, forKey: Keys.recordingConfigurationWarningRegistration.rawValue)
            } catch {
                assertionFailure("Could not encode recording warning registration: \(error)")
            }
        }
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
    /// install: onboarding shows again, presentation and notification settings
    /// revert to defaults, and UI continuity snapshots are forgotten.
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
        case showsRecordedLocationDots = "where.showsRecordedLocationDots"
        case theme = "where.theme"
        case showsLocationForecastsOnLocationsTab = "where.showsLocationForecastsOnLocationsTab"
        case remindersEnabled = "where.remindersEnabled"
        case reminderHour = "where.reminderHour"
        case reminderMinute = "where.reminderMinute"
        case summaryEnabled = "where.summaryEnabled"
        case summaryHour = "where.summaryHour"
        case summaryMinute = "where.summaryMinute"
        case issueAlertsEnabled = "where.issueAlertsEnabled"
        case sharesCrashReports = "where.diagnostics.sharesCrashReports"
        case sharesSessionReplays = "where.diagnostics.sharesSessionReplays"
        case remoteLogLevel = "where.diagnostics.remoteLogLevel"
        case remoteLogMetadataPolicy = "where.diagnostics.remoteLogMetadataPolicy"
        case recordingConfigurationWarningRegistration =
            "where.recordingConfigurationWarningRegistration"
        case driftThresholdMeters = "where.driftThresholdMeters"
        case lastSeenLocationDayCounts = "where.lastSeenLocationDayCounts"
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }
}
