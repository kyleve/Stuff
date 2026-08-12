import Foundation
import Observation
import PeriscopeCore
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
///   and the data-issue count (drives the Locations tab's Resolve toolbar
///   badge) → scene-scoped ``YearReportModel`` (owned by `MainTabs`, created
///   only once the real UI is on screen);
/// - the Resolve issue list → view-scoped ``ResolveModel``;
/// - the reminder/summary editing surface → view-scoped ``RemindersSettingsModel``;
/// - backup export/import progress → view-scoped ``BackupModel``.
///
/// A session only exists once the app is logged in to a scope: `WhereModel`
/// creates it in the launch's `start-session` step and drops it on reset (and
/// on entering demo mode), so `services` is non-optional and there are no
/// pre-attach nil guards. Logged-in views read it via
/// `@Environment(WhereSession.self)`; the `TabView` renders only at `.ready`
/// and onboarding runs *before* the scope is resolved, so the session is always
/// present wherever those views appear. It also vends `services` / `preferences` / `now`
/// so `MainTabs` can build the scene's `YearReportModel` (and the tabs their
/// view-scoped models) from the injected coordinator.
@MainActor
@Observable
public final class WhereSession {
    /// A process-unique, monotonically increasing identity for this session.
    /// `RootView` keys `MainTabs` (and thus the scene-scoped `YearReportModel`) on
    /// it, so a reset that rebuilds the session forces a fresh scene. Unlike an
    /// address-derived `ObjectIdentifier`, a monotonic token is never reused
    /// within the process — a session freed and reallocated at the same address
    /// gets a new token, so the scene can't fail to rebuild on a collision.
    public let id: SessionID

    /// The current installation's locally applied recording state. One value carries the
    /// resolved policy, physical status, and durable acknowledgement together; `.unavailable`
    /// means Core failed closed because it could not prove that agreement.
    public private(set) var recordingRuntimeState: RecordingDeviceRuntimeState = .unavailable

    /// Whether background GPS ingestion is currently attached. Derived from the applied state,
    /// so it cannot drift from the configuration Core durably acknowledged.
    public var isTracking: Bool {
        guard case let .applied(configuration) = recordingRuntimeState else { return false }
        return configuration.device.status == .recording
    }

    public var isCurrentDeviceRemoved: Bool {
        if case .removed = recordingRuntimeState { true } else { false }
    }

    /// Stable installation identity used by the Devices settings screen to mark
    /// the current row and prevent archiving it.
    public var currentRecordingDeviceID: RecordingDeviceID {
        services.recording.currentDevice.id
    }

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
    private let installationContextStore: any InstallationRecordingContextStoring

    /// The persisted user intent (tracking, reminder/summary schedules) the
    /// coordinator applies at launch/foreground. Owned by `WhereModel` and shared
    /// by reference so onboarding (model), the coordinator, and the view-scoped
    /// editing models all read/write the same store. Exposed so `MainTabs` can
    /// thread it into the scene's `YearReportModel`.
    let preferences: WherePreferences

    /// The coordinator's notion of "now". Not used by the coordinator itself; it
    /// vends the injected clock to the scene's `YearReportModel` (calendar /
    /// missing-day math) so previews/tests can pin a deterministic date.
    let now: @Sendable () -> Date

    /// `@ObservationIgnored` (it's plumbing, not observable UI state) and
    /// `nonisolated(unsafe)` so the `deinit` can cancel it. The unsafety is sound:
    /// every read/write is on the main actor except the `deinit`, which by
    /// definition runs with no other live references, so there is no concurrent
    /// access to race.
    @ObservationIgnored private nonisolated(unsafe) var authorizationTask: Task<Void, Never>?

    /// Mirrors only successfully applied current-device configurations emitted by Core.
    @ObservationIgnored private nonisolated(unsafe) var recordingConfigurationTask:
        Task<Void, Never>?

    /// Observes `dataChangeUpdates()` to keep ``regionStyles`` in sync with the
    /// store's picked region appearances. Same `nonisolated(unsafe)` rationale as
    /// `authorizationTask` — only touched on the main actor except `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var regionStyleTask: Task<Void, Never>?

    /// The user's picked region looks, resolved for the view environment (seeded
    /// into `whereBroadwayRoot(regionStyles:)` by `RootView`). Loaded at launch
    /// and kept live on every store change, so a Settings edit or a synced pick
    /// from another device restyles the UI without a relaunch.
    public private(set) var regionStyles: RegionStyleResolver = .default

    private static let logger = WhereLog.session(WhereSessionLog.self)

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
    private var warnedIssueAlertsUnauthorized = false

    /// Whether this session has performed its explicit, idempotent registration operation.
    private var didRegisterRecordingDevice = false
    /// Orders local recording intents across permission prompts; a newer Off must not be
    /// overwritten when an earlier On resumes after the prompt.
    private var recordingIntentSequence: UInt64 = 0
    /// Last controller-ordered runtime emission applied to presentation state.
    private var lastRecordingRuntimeSequence: UInt64?

    /// Latest resolved desired policy for this installation, available only after Core applies
    /// and acknowledges it. This gates foreground capture without a second mutable mirror.
    private var recordingEnabled: Bool {
        guard case let .applied(configuration) = recordingRuntimeState else { return false }
        return configuration.localAutomaticRecordingEnabled == true
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

    /// Build a coordinator over the scope the app is logged in to. The
    /// designated initializer: taking the whole scope is what guarantees the
    /// services and the preferences a session reads belong to the same world.
    init(
        scope: WhereScope,
        installationContextStore: (any InstallationRecordingContextStoring)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        id = Self.mintID()
        services = scope.services
        preferences = scope.preferences
        self.now = now
        if let installationContextStore {
            self.installationContextStore = installationContextStore
        } else {
            let registeredAt = now()
            self.installationContextStore = InMemoryInstallationRecordingContextStore(
                context: InstallationRecordingContext(
                    currentDevice: scope.services.recording.currentDevice,
                    registeredAt: registeredAt,
                    recordingChoice: .on(enabledAt: registeredAt),
                    isRejoining: false,
                ),
            )
        }
    }

    /// Build a coordinator over a loose service layer, wrapping it in a scope.
    /// For previews and tests that drive the coordinator directly and have no
    /// reason to name the scope; the app always has one.
    ///
    /// The wrapper scope never opens a log store, so nothing is ever registered
    /// on the logging system it names — which is why this doesn't ask the
    /// caller for one.
    public convenience init(
        services: WhereServices,
        preferences: WherePreferences,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.init(
            scope: .fake(
                services: services,
                preferences: preferences,
                logSystem: .shared,
            ),
            now: now,
        )
    }

    /// Cancel the authorization observer when the session is dropped (e.g. the
    /// reset teardown rebuilds a fresh session over the same retained services).
    /// Each session subscribes to its own `authorizationUpdates` stream (fanned
    /// out by `AuthorizationStatusBroadcaster`); cancelling here tears this
    /// session's subscription down promptly rather than letting the task linger
    /// until the next status change resumes it.
    deinit {
        authorizationTask?.cancel()
        recordingConfigurationTask?.cancel()
        regionStyleTask?.cancel()
    }

    /// Sync authorization, resume tracking if appropriate, apply the reminder /
    /// summary schedules, and republish the widget snapshot. Safe to call
    /// repeatedly; the authorization observer is only set up once.
    ///
    /// This is the imperative equivalent of `WhereLaunch.plan(for:)`'s coordinator
    /// work steps, kept for previews/tests that drive the coordinator directly
    /// without a `LifecycleRunner`. Report/data-issue loading is *not* here — the
    /// scene's `YearReportModel` owns that and starts it when the UI appears.
    public func start() async {
        await syncAuthorization()
        observeAuthorizationChanges()
        observeRecordingConfigurationChanges()
        await seedRegionStyles()
        observeRegionStyleChanges()
        await reconcileTracking()
        await captureTodayIfNeeded()
        await applyReminderConfiguration()
        await applySummaryConfiguration()
        await applyIssueAlertConfiguration()
        // Republish the widget snapshot from whatever is already on disk so a
        // cold launch with no writes this session doesn't leave the widget
        // blank or showing the previous day's "today".
        await refreshWidgetSnapshot()
    }

    /// Refresh state that can change while the app is away: authorization +
    /// tracking, the reminder/summary schedules (notification permission edits),
    /// and the widget snapshot (calendar-day rollover). The scene's `YearReportModel`
    /// separately re-pulls the report on `.active`.
    public func appBecameActive() async {
        await Self.logger.measure(.foregroundRefresh, budget: .seconds(5)) {
            await syncAuthorization()
            await reconcileTracking()
            await captureTodayIfNeeded()
            await applyReminderConfiguration()
            await applySummaryConfiguration()
            await applyIssueAlertConfiguration()
            // The calendar day may have rolled over while backgrounded;
            // recompute so the widget's "today" reflects the current day rather
            // than stale foreground state.
            await refreshWidgetSnapshot()
        }
    }

    /// Republish the widget snapshot from whatever is on disk. A launch step
    /// in its own right (see `WhereLaunch.plan(for:)`).
    public func refreshWidgetSnapshot() async {
        await services.widgets.configureTheme(preferences.theme)
        await services.widgets.refreshIfStale()
    }

    /// Republish widgets immediately when Appearance changes, without waiting
    /// for another data write or foreground refresh.
    func publishTheme(_ theme: WhereTheme) async {
        await services.widgets.publishTheme(theme)
    }

    /// Read the current authorization status from the ingestor into our
    /// observable state. Does not surface the permission alert — that's
    /// reserved for explicit user actions. A launch step (see
    /// `WhereLaunch.plan(for:)`).
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
                Self.logger { .whenInUseOnly }
            case .denied, .restricted:
                Self.logger {
                    .locationAccessDenied(status: String(describing: authorizationStatus))
                }
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

    /// Load the user's picked region appearances into ``regionStyles`` so the
    /// UI resolves them everywhere it renders a region. A launch step (see
    /// `WhereLaunch.plan(for:)`); also re-run on every store change via
    /// `observeRegionStyleChanges()`. On failure it keeps the last good resolver
    /// (honest degraded state) and logs.
    func seedRegionStyles() async {
        do {
            let primary = try await services.primaryRegions()
            regionStyles = RegionStyleResolver(primaryRegions: primary)
        } catch {
            Self.logger(attachments: [.error(error, name: "region-styles-error")]) {
                .regionStylesLoadFailed(description: error.localizedDescription)
            }
        }
    }

    /// Subscribe to store changes (local commits + remote CloudKit imports) so a
    /// customized region's look stays live — a Settings edit or a synced pick on
    /// another device reloads ``regionStyles``. Idempotent.
    func observeRegionStyleChanges() {
        guard regionStyleTask == nil else { return }
        let updates = services.dataChangeUpdates()
        regionStyleTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard let self else { break }
                await seedRegionStyles()
            }
        }
    }

    /// Observe Core's focused policy reconciliation output. The controller emits only after
    /// physical GPS state and its target-owned advisory check-in agree, so this mirror never has
    /// to infer state from an arbitrary store-change notification.
    private func observeRecordingConfigurationChanges() {
        guard recordingConfigurationTask == nil else { return }
        let updates = services.recording.runtimeUpdates()
        recordingConfigurationTask = Task { @MainActor [weak self] in
            for await update in updates {
                guard let self else { break }
                applyRecordingRuntimeUpdate(update)
            }
        }
    }

    /// Start or stop GPS ingestion so it matches the user's intent and the
    /// current authorization. Tracking only runs with Always authorization. A
    /// launch step (see `WhereLaunch.plan(for:)`).
    func reconcileTracking() async {
        observeRecordingConfigurationChanges()
        let wasTracking = isTracking
        do {
            await services.recording.startMonitoringChanges()
            if didRegisterRecordingDevice {
                _ = try await services.recording.reconcile(
                    authorization: authorizationStatus,
                )
            } else {
                _ = try await services.recording.register(
                    authorization: authorizationStatus,
                )
                didRegisterRecordingDevice = true
            }
            await synchronizeRecordingRuntimeState()
            if isTracking, !wasTracking {
                Self.logger { .backgroundTrackingStarted }
            } else if !isTracking, wasTracking {
                Self.logger { .backgroundTrackingStopped }
            }
        } catch {
            // Core fails closed and stops its source. Keep the UI mirror equally honest.
            didRegisterRecordingDevice = false
            await synchronizeRecordingRuntimeState()
            Self.logger(attachments: [.error(error, name: "recording-reconcile-error")]) {
                .recordingReconcileFailed(description: error.localizedDescription)
            }
        }
    }

    private func synchronizeRecordingRuntimeState() async {
        guard let update = await services.recording.currentRuntimeUpdate() else { return }
        applyRecordingRuntimeUpdate(update)
    }

    private func applyRecordingRuntimeUpdate(_ update: RecordingDeviceRuntimeUpdate) {
        if let lastRecordingRuntimeSequence,
           update.sequence <= lastRecordingRuntimeSequence
        {
            return
        }
        lastRecordingRuntimeSequence = update.sequence
        recordingRuntimeState = update.state
        if case .unavailable = update.state {
            didRegisterRecordingDevice = false
        } else if case .removed = update.state {
            didRegisterRecordingDevice = false
        }
    }

    /// Fill in today with a one-shot GPS fix if the day has no GPS sample yet,
    /// so opening the app on a fresh morning doesn't leave the calendar blank
    /// until passive tracking next fires. Gated on the resolved recording policy
    /// and a usable authorization (When-In-Use is enough for a foreground fix —
    /// notably the only way When-In-Use users get any data). The ingestor is
    /// non-blocking and reconciles widgets / reminders + pings the read signal
    /// on persist. A launch step (see `WhereLaunch.plan(for:)`); also runs on
    /// every foreground.
    func captureTodayIfNeeded() async {
        guard recordingEnabled, authorizationStatus.allowsForegroundFix else { return }
        await services.ingestor.captureTodayIfNeeded(now: now())
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
            Self.logger { .permissionGranted(status: String(describing: authorizationStatus)) }
        }
    }

    /// Turn on background tracking. Records the intent, requests permission if
    /// needed, then reconciles — `isTracking` only flips on once Always
    /// authorization is in hand and GPS is actually running. When only
    /// When-In-Use is granted the indicator guides the user to Settings; on a
    /// hard denial the Settings alert is surfaced.
    public func startTracking() async {
        do {
            try await setRecordingEnabled(true)
        } catch {
            Self.logger(attachments: [.error(error, name: "recording-enable-error")]) {
                .recordingReconcileFailed(description: error.localizedDescription)
            }
        }
    }

    public func stopTracking() async {
        do {
            try await setRecordingEnabled(false)
        } catch {
            Self.logger(attachments: [.error(error, name: "recording-disable-error")]) {
                .recordingReconcileFailed(description: error.localizedDescription)
            }
        }
    }

    /// Current synced device list. Registration is an explicit launch operation.
    public func recordingDevices() async throws -> [RecordingDeviceConfiguration] {
        try await services.recording.devices()
    }

    /// Persist and apply this installation's local recording choice.
    public func setRecordingEnabled(_ enabled: Bool) async throws {
        let (sequence, overflow) = recordingIntentSequence.addingReportingOverflow(1)
        precondition(!overflow, "Recording intent sequence exhausted UInt64.")
        recordingIntentSequence = sequence
        try installationContextStore.setAutomaticRecordingEnabled(enabled)

        var permissionRequestFailed = false
        if enabled {
            do {
                try await services.ingestor.requestPermission()
            } catch {
                permissionRequestFailed = true
            }
            await syncAuthorization()
        }
        guard sequence == recordingIntentSequence else { return }
        let configuration = try await services.recording.setAutomaticRecordingEnabled(
            enabled,
            authorization: authorizationStatus,
        )
        await synchronizeRecordingRuntimeState()
        permissionDenied = enabled && permissionRequestFailed
        if configuration.localAutomaticRecordingEnabled == true, isTracking {
            Self.logger { .trackingEnabled }
        } else if configuration.localAutomaticRecordingEnabled == false {
            Self.logger { .stoppedBackgroundTracking }
        }
    }

    public func renameRecordingDevice(
        _ deviceID: RecordingDeviceID,
        to nickname: String,
    ) async throws {
        _ = try await services.recording.rename(deviceID, to: nickname)
    }

    public func removeRecordingDevice(
        _ deviceID: RecordingDeviceID,
    ) async throws {
        _ = try await services.recording.remove(deviceID)
    }

    func prepareDeviceRejoin() async throws {
        authorizationTask?.cancel()
        recordingConfigurationTask?.cancel()
        regionStyleTask?.cancel()
        try await services.recording.retireForRejoin()
    }

    /// Push the persisted reminder intent to the reminder reconciler and warn if
    /// notifications are enabled but unauthorized. Reads `WherePreferences`
    /// directly (the single source of truth the `RemindersSettingsModel` also
    /// writes), so it re-applies whatever the user last chose. A launch step
    /// (see `WhereLaunch.plan(for:)`); also runs on every foreground.
    func applyReminderConfiguration() async {
        let enabled = preferences.remindersEnabled
        // The reminder reconciler also owns the app-icon badge, whose value folds
        // in the unresolved-issue count — so it needs the issue-alert intent and
        // the current drift threshold the scan runs at.
        await services.reminders.configure(
            enabled: enabled,
            time: preferences.reminderTime,
            issueAlertsEnabled: preferences.issueAlertsEnabled,
            driftThresholdMeters: Double(preferences.driftThresholdMeters),
        )
        let authorized = await services.reminders.isAuthorized()
        if enabled, !authorized {
            if !warnedRemindersUnauthorized {
                Self.logger { .remindersUnauthorized }
                warnedRemindersUnauthorized = true
            }
        } else {
            warnedRemindersUnauthorized = false
        }
    }

    /// Push the persisted daily-summary intent to the summary reconciler and warn
    /// if enabled but unauthorized. Reads `WherePreferences` directly, mirroring
    /// `applyReminderConfiguration()`. A launch step (see `WhereLaunch.plan(for:)`);
    /// also runs on every foreground.
    func applySummaryConfiguration() async {
        let enabled = preferences.summaryEnabled
        await services.summary.configure(enabled: enabled, time: preferences.summaryTime)
        let authorized = await services.reminders.isAuthorized()
        if enabled, !authorized {
            if !warnedSummaryUnauthorized {
                Self.logger { .summaryUnauthorized }
                warnedSummaryUnauthorized = true
            }
        } else {
            warnedSummaryUnauthorized = false
        }
    }

    /// Push the persisted issue-alert intent to the issue-alert reconciler and
    /// warn if enabled but unauthorized. Fires the alert at the evening reminder
    /// time and scans at the current drift threshold. Reads `WherePreferences`
    /// directly, mirroring `applyReminderConfiguration()`. A launch step (see
    /// `WhereLaunch.plan(for:)`); also runs on every foreground.
    func applyIssueAlertConfiguration() async {
        let enabled = preferences.issueAlertsEnabled
        await services.issueAlerts.configure(
            enabled: enabled,
            time: preferences.reminderTime,
            driftThresholdMeters: Double(preferences.driftThresholdMeters),
        )
        let authorized = await services.reminders.isAuthorized()
        if enabled, !authorized {
            if !warnedIssueAlertsUnauthorized {
                Self.logger { .issueAlertsUnauthorized }
                warnedIssueAlertsUnauthorized = true
            }
        } else {
            warnedIssueAlertsUnauthorized = false
        }
    }

    /// Erase synced user data and reset the coordinator's observable state to a
    /// clean slate. A thin pass-through to `WhereServices.reset()`, which owns
    /// *what* gets cleared (device identities + user-data transaction + pending
    /// fixes + derived-state reconciliation); the coordinator only mirrors the outcome. The
    /// scene's `YearReportModel` is torn down and rebuilt by the relaunch, so no
    /// report/issue state needs clearing here. The data half of the reset/erase
    /// teardown (see `WhereLaunch.resetPlan(for:)`); throws on persistence failure
    /// so the reset step parks the launcher in `.failed` rather than silently
    /// half-erasing.
    public func eraseSession() async throws {
        let authorizationObserver = authorizationTask
        let dataObserver = regionStyleTask
        authorizationTask = nil
        regionStyleTask = nil
        authorizationObserver?.cancel()
        dataObserver?.cancel()
        await authorizationObserver?.value
        await dataObserver?.value

        do {
            try await services.reset()
        } catch let error as WhereServices.ResetCleanupError {
            // Synced erasure already committed. Keep the old installation context available to
            // a later cleanup retry, but never revive this session's observers or recording: the
            // teardown step must release the scope and App Intents before surfacing the terminal
            // partial-success state.
            recordingRuntimeState = .unavailable
            throw error
        } catch {
            // The data transaction rolled back. This session remains valid for an explicit retry,
            // so restore its live observers along with Core's operation gate.
            recordingRuntimeState = .unavailable
            await reconcileTracking()
            observeAuthorizationChanges()
            observeRegionStyleChanges()
            throw error
        }
        recordingRuntimeState = .unavailable
        Self.logger { .erasedSession }
    }
}
