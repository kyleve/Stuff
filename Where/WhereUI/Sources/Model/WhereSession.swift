import Foundation
import LogKit
import Observation
#if DEBUG
    import SwiftDataInspector
#endif
import WhereCore

/// The always-on, logged-in coordinator for the Where app: GPS / permission
/// state, the launch-time reminder + daily-summary *application*, the widget
/// snapshot republish, and the erase/reset pass-through. Every mutation funnels
/// through a `WhereServices` collaborator so the views stay free of persistence
/// and CoreLocation details.
///
/// It deliberately holds **no presentation state**. Everything scoped to the
/// visible UI lives in child observables the scene / views own:
/// - the selected year's `YearReport`, ranking, missing days, day-write intents,
///   and the Resolve badge count → scene-scoped ``ReportModel`` (owned by
///   `MainTabs`, created only once the real UI is on screen);
/// - the Resolve issue list → view-scoped ``ResolveModel``;
/// - the reminder/summary editing surface → view-scoped ``RemindersSettingsModel``;
/// - backup export/import progress → view-scoped ``BackupModel``.
///
/// A session only exists once the store is open: `WhereModel` creates it in the
/// launch's `open-store` step and drops it on reset, so `services` is
/// non-optional and there are no pre-attach nil guards. Logged-in views read it
/// via `@Environment(WhereSession.self)`; the `TabView` renders only at `.ready`
/// and onboarding runs after `open-store`, so the session is always present
/// wherever those views appear. It also vends `services` / `preferences` / `now`
/// so `MainTabs` can build the scene's `ReportModel` (and the tabs their
/// view-scoped models) from the injected coordinator.
@MainActor
@Observable
public final class WhereSession {
    /// A process-unique, monotonically increasing identity for this session.
    /// `RootView` keys `MainTabs` (and thus the scene-scoped `ReportModel`) on
    /// it, so a reset that rebuilds the session forces a fresh scene. Unlike an
    /// address-derived `ObjectIdentifier`, a monotonic token is never reused
    /// within the process — a session freed and reallocated at the same address
    /// gets a new token, so the scene can't fail to rebuild on a collision.
    public let id: SessionID

    /// Whether background GPS ingestion is currently attached. Reflects reality
    /// (authorization + the user's intent), not just the last button tap.
    public private(set) var isTracking = false

    /// The latest known location authorization status, kept live via
    /// `LocationIngestor.authorizationUpdates()`.
    public private(set) var authorizationStatus: LocationAuthorizationStatus = .notDetermined

    /// Set when a location-permission request comes back denied/restricted,
    /// so the UI can offer to open Settings.
    public var permissionDenied = false

    /// The services every mutation funnels through. Non-optional: a session only
    /// exists once `WhereModel` has assembled the service layer. Exposed so
    /// `MainTabs` / the tabs can build their scoped models from the injected
    /// coordinator.
    let services: WhereServices

    /// The persisted user intent (tracking, reminder/summary schedules) the
    /// coordinator applies at launch/foreground. Owned by `WhereModel` and shared
    /// by reference so onboarding (model), the coordinator, and the view-scoped
    /// editing models all read/write the same store. Exposed so `MainTabs` can
    /// thread it into the scene's `ReportModel`.
    let preferences: WherePreferences

    /// The coordinator's notion of "now". Not used by the coordinator itself; it
    /// vends the injected clock to the scene's `ReportModel` (calendar /
    /// missing-day math) so previews/tests can pin a deterministic date.
    let now: @Sendable () -> Date

    /// `@ObservationIgnored` (it's plumbing, not observable UI state) and
    /// `nonisolated(unsafe)` so the `deinit` can cancel it. The unsafety is sound:
    /// every read/write is on the main actor except the `deinit`, which by
    /// definition runs with no other live references, so there is no concurrent
    /// access to race.
    @ObservationIgnored private nonisolated(unsafe) var authorizationTask: Task<Void, Never>?

    private static let logger = WhereLog.channel(.session)

    /// The authorization the degradation warning was last evaluated against.
    /// `syncAuthorization()` runs on every foreground, so warning only on a
    /// *change* keeps a steady degraded state (e.g. When-In-Use) from repeating
    /// the same line on each one.
    private var lastWarnedAuthorization: LocationAuthorizationStatus?

    /// Whether the "enabled but notifications not authorized" warning has been
    /// emitted for the current state, so it fires on entry into that state
    /// rather than on every configuration apply (which also runs per foreground).
    private var warnedRemindersUnauthorized = false
    private var warnedSummaryUnauthorized = false

    /// Persisted user intent to track in the background. Effective tracking is
    /// this AND `.always` authorization; we default to `true` so that, once the
    /// user grants Always, tracking resumes automatically on every launch.
    private var wantsTracking: Bool {
        get { preferences.wantsTracking }
        set { preferences.wantsTracking = newValue }
    }

    /// A process-unique session identity. A typed token rather than a raw `Int`
    /// so it can't be transposed with any other counter, and `Hashable` so
    /// SwiftUI's `.id(_:)` can key a subtree on it.
    public struct SessionID: Hashable, Sendable {
        fileprivate let value: Int
    }

    /// Monotonic source for `SessionID`s. `@MainActor`-isolated (the enclosing
    /// class is), so minting from `init` needs no extra synchronization.
    private static var nextRawID = 0

    private static func mintID() -> SessionID {
        defer { nextRawID += 1 }
        return SessionID(value: nextRawID)
    }

    /// Build a coordinator over an already-assembled service layer.
    public init(
        services: WhereServices,
        preferences: WherePreferences = WherePreferences(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        id = Self.mintID()
        self.services = services
        self.preferences = preferences
        self.now = now
    }

    /// Cancel the authorization observer when the session is dropped (e.g. the
    /// reset teardown rebuilds a fresh session over the same retained services).
    /// Each session subscribes to its own `authorizationUpdates` stream (fanned
    /// out by `AuthorizationStatusBroadcaster`); cancelling here tears this
    /// session's subscription down promptly rather than letting the task linger
    /// until the next status change resumes it.
    deinit {
        authorizationTask?.cancel()
    }

    /// Sync authorization, resume tracking if appropriate, apply the reminder /
    /// summary schedules, and republish the widget snapshot. Safe to call
    /// repeatedly; the authorization observer is only set up once.
    ///
    /// This is the imperative equivalent of `WhereLaunch.sequence`'s coordinator
    /// work steps, kept for previews/tests that drive the coordinator directly
    /// without a `LifecycleRunner`. Report/data-issue loading is *not* here — the
    /// scene's `ReportModel` owns that and starts it when the UI appears.
    public func start() async {
        await syncAuthorization()
        observeAuthorizationChanges()
        await reconcileTracking()
        await applyReminderConfiguration()
        await applySummaryConfiguration()
        // Republish the widget snapshot from whatever is already on disk so a
        // cold launch with no writes this session doesn't leave the widget
        // blank or showing the previous day's "today".
        await refreshWidgetSnapshot()
    }

    /// Refresh state that can change while the app is away: authorization +
    /// tracking, the reminder/summary schedules (notification permission edits),
    /// and the widget snapshot (calendar-day rollover). The scene's `ReportModel`
    /// separately re-pulls the report on `.active`.
    public func appBecameActive() async {
        await syncAuthorization()
        await reconcileTracking()
        await applyReminderConfiguration()
        await applySummaryConfiguration()
        // The calendar day may have rolled over while backgrounded; recompute
        // so the widget's "today" reflects the current day rather than stale
        // foreground state.
        await refreshWidgetSnapshot()
    }

    /// Republish the widget snapshot from whatever is on disk. A launch step
    /// in its own right (see `WhereLaunch.sequence`).
    public func refreshWidgetSnapshot() async {
        await services.widgets.refreshIfStale()
    }

    /// Read the current authorization status from the ingestor into our
    /// observable state. Does not surface the permission alert — that's
    /// reserved for explicit user actions. A launch step (see
    /// `WhereLaunch.sequence`).
    func syncAuthorization() async {
        authorizationStatus = await services.ingestor.authorizationStatus()
        warnIfAuthorizationDegraded()
    }

    /// Emit a warning when the live authorization can't support background
    /// tracking, so the in-app log explains why GPS isn't running. Only fires on
    /// an actual status change — `syncAuthorization()` polls on every foreground,
    /// so an unconditional warn would repeat the same line each time. `always`
    /// and the transient `notDetermined` are expected states and stay quiet (but
    /// still update the dedup marker, so re-entering a degraded state warns).
    private func warnIfAuthorizationDegraded() {
        guard authorizationStatus != lastWarnedAuthorization else { return }
        lastWarnedAuthorization = authorizationStatus
        switch authorizationStatus {
            case .always, .notDetermined:
                break
            case .whenInUse:
                Self.logger.warning(
                    "Location authorized for When-In-Use only; background tracking unavailable",
                )
            case .denied, .restricted:
                Self.logger.warning(
                    "Location access \(authorizationStatus); background tracking unavailable",
                )
        }
    }

    /// Subscribe to live authorization changes (prompt results, Settings-app
    /// edits) so the indicator and tracking state stay in sync. Idempotent.
    func observeAuthorizationChanges() {
        guard authorizationTask == nil else { return }
        // Capture the value-type services locally so the long-lived stream loop
        // keeps `self` weak (an injected services reference, not the session).
        let services = services
        authorizationTask = Task { @MainActor [weak self] in
            let updates = await services.ingestor.authorizationUpdates()
            for await status in updates {
                guard let self else { break }
                authorizationStatus = status
                warnIfAuthorizationDegraded()
                await reconcileTracking()
            }
        }
    }

    /// Start or stop GPS ingestion so it matches the user's intent and the
    /// current authorization. Tracking only runs with Always authorization. A
    /// launch step (see `WhereLaunch.sequence`).
    func reconcileTracking() async {
        let wasTracking = isTracking
        if wantsTracking, authorizationStatus.allowsBackgroundTracking {
            await services.ingestor.start()
            isTracking = true
            if !wasTracking { Self.logger.info("Background tracking started") }
        } else {
            await services.ingestor.stop()
            isTracking = false
            if wasTracking { Self.logger.info("Background tracking stopped") }
        }
    }

    /// Explicitly (re)request location access, e.g. from the "Grant location
    /// access" button. Drives the system prompt when possible, then syncs the
    /// status and reconciles tracking so the UI reflects the outcome.
    public func requestPermission() async {
        do {
            try await services.ingestor.requestPermission()
            permissionDenied = false
        } catch {
            // `.denied` / `.restricted` mean re-prompting won't help, so the UI
            // routes the user to the Settings app.
            permissionDenied = true
        }
        await syncAuthorization()
        await reconcileTracking()
        if authorizationStatus.allowsBackgroundTracking {
            Self.logger.info("Location permission granted (\(authorizationStatus))")
        }
    }

    /// Turn on background tracking. Records the intent, requests permission if
    /// needed, then reconciles — `isTracking` only flips on once Always
    /// authorization is in hand and GPS is actually running. When only
    /// When-In-Use is granted the indicator guides the user to Settings; on a
    /// hard denial the Settings alert is surfaced.
    public func startTracking() async {
        wantsTracking = true
        do {
            try await services.ingestor.requestPermission()
            permissionDenied = false
        } catch {
            permissionDenied = true
        }
        await syncAuthorization()
        await reconcileTracking()
        if authorizationStatus.allowsBackgroundTracking {
            Self.logger.info("Tracking enabled with background authorization")
        }
    }

    public func stopTracking() async {
        wantsTracking = false
        await services.ingestor.stop()
        isTracking = false
        Self.logger.info("Stopped background tracking")
    }

    /// Push the persisted reminder intent to the reminder reconciler and warn if
    /// notifications are enabled but unauthorized. Reads `WherePreferences`
    /// directly (the single source of truth the `RemindersSettingsModel` also
    /// writes), so it re-applies whatever the user last chose. A launch step
    /// (see `WhereLaunch.sequence`); also runs on every foreground.
    func applyReminderConfiguration() async {
        let enabled = preferences.remindersEnabled
        await services.reminders.configure(enabled: enabled, time: preferences.reminderTime)
        let authorized = await services.reminders.isAuthorized()
        if enabled, !authorized {
            if !warnedRemindersUnauthorized {
                Self.logger.warning("Logging reminders enabled but notifications not authorized")
                warnedRemindersUnauthorized = true
            }
        } else {
            warnedRemindersUnauthorized = false
        }
    }

    /// Push the persisted daily-summary intent to the summary reconciler and warn
    /// if enabled but unauthorized. Reads `WherePreferences` directly, mirroring
    /// `applyReminderConfiguration()`. A launch step (see `WhereLaunch.sequence`);
    /// also runs on every foreground.
    func applySummaryConfiguration() async {
        let enabled = preferences.summaryEnabled
        await services.summary.configure(enabled: enabled, time: preferences.summaryTime)
        let authorized = await services.reminders.isAuthorized()
        if enabled, !authorized {
            if !warnedSummaryUnauthorized {
                Self.logger.warning("Daily summary enabled but notifications not authorized")
                warnedSummaryUnauthorized = true
            }
        } else {
            warnedSummaryUnauthorized = false
        }
    }

    /// Erase all persisted data and reset the coordinator's observable state to a
    /// clean slate. A thin pass-through to `WhereServices.reset()`, which owns
    /// *what* gets cleared (GPS stop + store wipe + reminder/badge reconcile +
    /// empty widget snapshot); the coordinator only mirrors the outcome. The
    /// scene's `ReportModel` is torn down and rebuilt by the relaunch, so no
    /// report/issue state needs clearing here. The data half of the reset/erase
    /// teardown (see `WhereLaunch.resetSequence`); throws on persistence failure
    /// so the reset step parks the launcher in `.failed` rather than silently
    /// half-erasing.
    public func eraseSession() async throws {
        try await services.reset()
        isTracking = false
        Self.logger.info("Erased session and reset state")
    }

    /// Drives the background-tracking `Toggle`. Reads the live `isTracking`
    /// state; assigning kicks off the matching async start/stop so the view can
    /// bind straight to it (`$session.trackingEnabled`) instead of building a
    /// closure-based `Binding`. `isTracking` stays the single source of truth.
    public var trackingEnabled: Bool {
        get { isTracking }
        set {
            Task { newValue ? await startTracking() : await stopTracking() }
        }
    }
}

#if DEBUG
    extension WhereSession {
        /// A read-only SwiftData inspector over the live store, for the DEBUG-only
        /// developer entry point in Settings. `nil` when the backing store isn't
        /// SwiftData (e.g. a preview/test fake), so the entry point hides itself.
        var swiftDataInspectorConfiguration: SwiftDataInspectorConfiguration? {
            guard let container = services.modelContainer else { return nil }
            return SwiftDataInspectorConfiguration(
                container: container,
                modelTypes: SwiftDataStore.inspectorModelTypes,
                title: Strings.settingsDebugInspectorTitle,
            )
        }
    }
#endif
