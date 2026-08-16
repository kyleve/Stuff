import LifecycleKit
import PeriscopeCore
import SwiftUI
import UserNotifications
import WhereCore

/// Stable identifiers for the nodes in `WhereLaunch.plan(for:)` and
/// `resetPlan(for:)`. Raw strings drift silently (a typo just creates a new,
/// untracked step); an enum makes each ID a compile-checked symbol and gives
/// the launch/reset parity tests a single source of truth.
public enum LaunchStepID: String, Sendable {
    /// First-run onboarding gate, at the head of the trunk: until the user
    /// chooses a world to work in, nothing downstream runs and no store is
    /// opened. Applies to every launch reason — a headless launch parks here
    /// rather than opening the user's store unseen.
    case onboarding
    /// Resolve the scope the launch runs against, opening the user's real
    /// store if they onboarded on an earlier launch — the trunk's logged-in
    /// scope. The splash's slow-launch caption most often shows here.
    case resolveScope = "resolve-scope"
    /// Build the logged-in session over the scope and fire the app's
    /// composition hook — promotes the trunk to the session scope.
    case startSession = "start-session"
    /// Read location authorization into the coordinator and start observing
    /// live authorization changes. The report + data-issue scan (and their
    /// store-change subscription) load with the scene now, not here — so a
    /// headless launch (no scene) never drives a refresh no UI consumes.
    case syncAuth = "sync-auth"
    /// Start or stop GPS ingestion to match the user's intent + authorization.
    case reconcileTracking = "reconcile-tracking"
    /// Take a one-shot GPS fix for today if none is logged yet, so opening the
    /// app on a fresh day fills the calendar in. Foreground-only — a headless
    /// launch shouldn't spend a fresh fix (a `.background` relaunch is itself
    /// the passive event); it runs once a scene promotes the launch.
    case captureToday = "capture-today"
    /// Push the logging-reminder schedule + badge (backlog + issue count) to
    /// the reconciler.
    case reminders
    /// Push the daily-summary recap to the reconciler.
    case summary
    /// Push the "issues to resolve" notification intent to its reconciler.
    case issueAlerts = "issue-alerts"
    /// Republish the widget snapshot from whatever is already on disk.
    case widgetSnapshot = "widget-snapshot"

    /// Reset teardown: pause GPS, erase synced user data, remove old device identities,
    /// discard pending fixes, and drop the session.
    case eraseData = "erase-data"
    /// Reset teardown: clear the installation context and persisted preferences
    /// that gate the relaunch (onboarding flag and reminder/summary schedules).
    case resetPreferences = "reset-preferences"
    /// Demo teardown: drop the demo world and hand the real one its durable
    /// log sink back.
    case exitDemo = "exit-demo"
    /// Retire a removed local identity, then re-drive onboarding with a fresh identity.
    case rejoinDevice = "rejoin-device"
}

/// Assembles the Where app's cold-launch plan and the `LifecycleRunner` that
/// drives it.
///
/// The plan is only the *prerequisites*; the destination — the real tab UI —
/// is `LifecycleContainer`'s `content` (see `RootView`), handed the
/// `WhereSession` the trunk produced once the runner reaches `.ready`.
///
/// The trunk begins with the onboarding gate — nothing may be built until the
/// user has chosen a world to work in — and its value then grows monotonically
/// by embedding: `ResolveScopeStep` mints the `WhereScope` the app is logged in
/// to, `StartSessionStep` promotes it to `WhereSession` (which carries the
/// scope's services non-optionally), and every downstream node takes the session as
/// its typed input. The compiler holds the ordering — a node cannot be
/// placed before its input exists, and only pass-through nodes (the
/// onboarding gate, `thenKeeping` steps, the detached fan) may skip, so a
/// skipped node can't leave a hole in the data flow.
@MainActor
public enum WhereLaunch {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    /// Start the built-in ambient sources (network path, thermal state, low
    /// power mode, app lifecycle, memory warnings, accessibility settings) on
    /// `system`. Called once from the app delegate at process launch — they
    /// describe the *process*, not a login, and are the one logging concern
    /// that isn't a scope's.
    ///
    /// The durable sink is a scope's (see `WhereScope`), and no scope exists
    /// yet at this point, so everything logged until one is resolved — these
    /// sources' opening snapshots included — reaches OSLog only. That is the
    /// cost of opening no store until the user asks for one. (Closing the
    /// pre-sink window properly — a bootstrap journal from process start — is
    /// tracked as a P0 in `Shared/Periscope/TODOs.md`.)
    public static func startAmbientLogging(on system: Periscope) {
        system.startDefaultAmbientSources()
    }

    /// Build the runner for `model`, launching for `reason`.
    ///
    /// `initializePrerequisites` runs the synchronous, must-exist-now launch
    /// wiring before any async node: the model's bootstrap installs the
    /// `CLLocationManager` (`prepareLocation()`) so a background relaunch's
    /// queued event isn't lost while the launch resolves a scope, and the
    /// foreground-notification presenter is registered so a reminder fired
    /// while Where is open still shows. Keeping both here (rather than in the
    /// app delegate) puts app-lifecycle wiring in one place. Neither opens a
    /// store or prompts for anything, so both are safe before the user has
    /// chosen a world.
    ///
    /// `onServicesReady` fires from the `start-session` step every time a
    /// session is (re)started over a scope — first launch, the fresh process
    /// after a failed (terminal) launch, and the in-process reset
    /// relaunch. The app uses it to
    /// hand the service layer to consumers WhereUI can't see (deriving and
    /// installing the App Intents stack — see the app's `AppDelegate`);
    /// previews and tests omit it.
    public static func makeLauncher(
        model: WhereModel,
        reason: LifecycleReason,
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> LifecycleRunner<WhereSession> {
        logger.runnerCreated(
            reason: .restricted(.technicalState, String(describing: reason)),
        )
        let runner = LifecycleRunner(
            reason: reason,
            initializePrerequisites: {
                model.prepareLocation()
                ForegroundNotificationPresenter.install()
            },
            plan: plan(for: model, onServicesReady: onServicesReady),
        )
        // Mirror detached-step failures into WhereLog: the runner only
        // records them on its observable `detachedFailures`, which nothing
        // renders — without this a throwing detached step would fail with no
        // trace in logs.
        DetachedFailureReporter.observe(runner)
        return runner
    }

    /// The typed launch plan. The trunk mirrors the imperative
    /// `WhereSession.start()` order (a parity test guards this); the only
    /// insertions are the `onboarding` gate at its head and the
    /// `resolve-scope` / `start-session` promotions, none of which `start()`
    /// models. The independent session-configuration steps fan out detached
    /// after the trunk — they take the session, return nothing, and never
    /// block `.ready`.
    ///
    /// Rooting at the gate is what makes the app's store open *lazily*: a user
    /// who hasn't onboarded parks here, and nothing downstream — including the
    /// store open — runs until they choose. `onServicesReady` fires from
    /// `start-session` whenever a session is (re)started (see `makeLauncher`);
    /// callers that only inspect the node list (the parity test) can rely on
    /// the default.
    ///
    /// Every step is composed `.measured()`, so each run is a budgeted
    /// Periscope span named after the step (see `MeasuredStep`) and a slow
    /// launch attributes to a step rather than to "launch". The onboarding
    /// gate is the one unmeasured node: it parks on the user, so its duration
    /// is a human's, not the app's.
    public static func plan(
        for model: WhereModel,
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> LaunchPlan<LaunchStepID, Void, WhereSession> {
        LaunchPlan(OnboardingGate(model: model))
            .then(ResolveScopeStep(model: model).measured())
            .then(StartSessionStep(model: model, onServicesReady: onServicesReady).measured())
            .thenKeeping(SyncAuthStep().measured())
            .thenKeeping(ReconcileTrackingStep().measured())
            .detached {
                CaptureTodayStep().measured()
                RemindersStep().measured()
                SummaryStep().measured()
                IssueAlertsStep().measured()
                WidgetSnapshotStep().measured()
            }
    }

    /// The reverse of `plan(for:)`: the teardown run by Settings' "Erase all
    /// data & reset", rooted at the session being torn down (Settings hands
    /// it in as the teardown input — no optional re-read). `LifecycleRunner
    /// .teardown` runs these nodes, then re-drives the launch plan from the
    /// top — which, with `hasOnboarded` now cleared, parks on the onboarding
    /// gate again, returning the app to its first-run state.
    public static func resetPlan(for model: WhereModel)
        -> LaunchPlan<LaunchStepID, WhereSession, Void>
    {
        LaunchPlan(EraseDataStep(model: model).measured())
            .then(ResetPreferencesStep(model: model).measured())
    }

    /// The teardown Settings' "Exit demo mode" runs, rooted at the demo
    /// session being left behind.
    ///
    /// Nothing is erased: a demo world was only ever in memory, so dropping it
    /// *is* the cleanup. The relaunch lands on the onboarding gate — the demo's
    /// `hasOnboarded` went with its preferences, and the user's real flag says
    /// whatever it always did, so someone who had already onboarded goes
    /// straight back to their data and everyone else gets the intro.
    public static func exitDemoPlan(for model: WhereModel)
        -> LaunchPlan<LaunchStepID, WhereSession, Void>
    {
        LaunchPlan(ExitDemoStep(model: model).measured())
    }

    public static func rejoinPlan(for model: WhereModel)
        -> LaunchPlan<LaunchStepID, WhereSession, Void>
    {
        LaunchPlan(RejoinDeviceStep(model: model).measured())
    }
}

/// Assembles the outside-world pieces a real `WhereScope` is built from: the
/// service layer over the app's one store, and the durable log store that
/// scope's records persist to.
///
/// A protocol because the app opens those *lazily* — only once the user has
/// chosen to use the app for real — so the assembly is reached through
/// `WhereModel` rather than handed in at launch, and a test that drives that
/// path needs to substitute a stack that touches no disk. Production is
/// ``WhereBootstrap``.
@MainActor
public protocol WhereScopeAssembling {
    /// Install the location manager without touching the store. Idempotent,
    /// and cheap enough to run on the synchronous launch path.
    func prepareLocation()

    /// Open the store and assemble the services over it. The app process's
    /// **one** store open.
    func makeServices() async throws -> WhereServices

    /// Open and retain the real store while onboarding remains dormant, then read synced device
    /// status without constructing services or activating location/App Intents.
    func discoverRecordingDevices() async throws -> [RecordingDevice]

    /// Open the durable log store the scope's records persist to, or `nil` for
    /// an assembly with no durable logging — previews and tests, which log
    /// through the in-memory pipeline and must leave no sink attached to the
    /// process-wide one.
    func makeLogStore() async throws -> PeriscopeStore?
}

/// Owns the assembly of the user's real world, so `WhereScope` and
/// `WhereModel` consume finished pieces rather than wiring up persistence and
/// CoreLocation themselves.
///
/// `prepareLocation()` runs synchronously as the runner's
/// `initializePrerequisites`, installing the `CLLocationManager` + delegate
/// early so a background relaunch's queued significant-change / visit event is
/// buffered (in `CoreLocationSource.sampleStream`) rather than dropped while
/// the store opens. `makeServices()` then opens the store off the main actor
/// and assembles the services from the two.
@MainActor
public final class WhereBootstrap: WhereScopeAssembling {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    private let installationContextStore: any InstallationRecordingContextStoring
    private let storeStorage: SwiftDataStore.Storage
    private let locationOutbox: any LocationOutbox
    private var locationSource: CoreLocationSource?
    private var preparedStore: SwiftDataStore?

    public init(
        installationContextStore: any InstallationRecordingContextStoring,
        storeStorage: SwiftDataStore.Storage,
        locationOutbox: any LocationOutbox,
    ) {
        self.installationContextStore = installationContextStore
        self.storeStorage = storeStorage
        self.locationOutbox = locationOutbox
    }

    /// Install the `CLLocationManager` + delegate right away, without touching
    /// the store. Idempotent.
    public func prepareLocation() {
        guard locationSource == nil else { return }
        locationSource = CoreLocationSource()
    }

    /// Open the SwiftData store (on a detached task so a slow open or first
    /// creation runs off the main actor the splash renders on) and assemble
    /// the services from it and the prepared location source. Throws on
    /// persistence failure so the `resolve-scope` step can surface it.
    ///
    /// This is the app process's **one** store open — everything else shares
    /// the instance by injection (the App Intents stack derives from these
    /// services via `WhereServices.forIntents(sharingStoreOf:)`; see the
    /// app's `AppDelegate`), so no second container ever races this one over
    /// the same store file.
    ///
    /// A failure is logged here as well as thrown: when the failing drive has
    /// been superseded (e.g. a foreground promotion cancelled it mid-open),
    /// the runner deliberately discards its error instead of parking in
    /// `.failed`, so without this line the failure would leave no trace
    /// anywhere.
    public func makeServices() async throws -> WhereServices {
        let source = locationSource ?? CoreLocationSource()
        locationSource = nil
        do {
            let installationContext = try installationContextStore.resolve()
            precondition(
                installationContext.automaticRecordingEnabled != nil,
                "A real scope cannot open before this installation confirms recording.",
            )
            let store = try await prepareStore()
            let services = try await WhereServices.make(
                store: store,
                locationSource: source,
                installationContext: installationContext,
                // The real world's seams, named here because this is the only
                // place that wants them: the demo scope builds the same stack
                // out of no-ops, and every test and preview gets no-ops by
                // default.
                reminderScheduler: UserNotificationReminderScheduler(),
                summaryScheduler: UserNotificationDailySummaryScheduler(),
                issueAlertScheduler: UserNotificationDataIssueAlertScheduler(),
                widgetRefresher: WidgetCenterTimelineRefresher(),
                locationOutbox: locationOutbox,
                importRecoveryPersistence: installationContextStore,
            )
            Self.logger.servicesAssembled()
            return services
        } catch {
            Self.logger.servicesAssemblyFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "assemble-error")],
            )
            throw error
        }
    }

    public func discoverRecordingDevices() async throws -> [RecordingDevice] {
        let readiness = CloudKitImportReadiness()
        if storeStorage == .cloudKit { readiness.start() }
        let store = try await prepareStore()
        if storeStorage == .cloudKit, await readiness.waitForImport() == false {
            throw CloudKitImportReadiness.Timeout()
        }
        return try await store.recordingDevices()
    }

    private func prepareStore() async throws -> SwiftDataStore {
        if let preparedStore { return preparedStore }
        let storeStorage = storeStorage
        let store = try await Task.detached(priority: .userInitiated) {
            try SwiftDataStore.make(storage: storeStorage)
        }.value
        preparedStore = store
        return store
    }

    /// Open the app's durable log store: `Periscope.store` on disk, plus this
    /// launch's crash journal beside it. Opened per scope rather than per
    /// process, because what a session persists depends on which world it is
    /// in — an in-memory world must leave nothing behind.
    public func makeLogStore() async throws -> PeriscopeStore? {
        try await PeriscopeStore.make(
            storage: Self.logStorage,
            session: .current(
                attributes: BuildInfo.current(bundle: .main).logSessionAttributes,
            ),
        )
    }

    /// Where a real scope's log store belongs. Under a test host it must stay
    /// in memory. A suite that logs in would otherwise write its
    /// records into the user's `Periscope.store`, and opening that from a test
    /// host's sandbox neither succeeds nor fails promptly — it stalls the
    /// bundle instead of failing it.
    ///
    /// The environment check lives here rather than in `PeriscopeCore` because
    /// a general-purpose logging framework has no business knowing what a test
    /// host is. This is the app's composition root choosing its own world, and
    /// `WhereBootstrap` is the only place that opens a durable one.
    @_spi(Testing) public nonisolated static var logStorage: PeriscopeStore.Storage {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .inMemory
        }
        return .onDisk
    }
}

/// Presents the app's local notifications (logging reminders, the daily summary,
/// the "issues to resolve" alert) even while Where is foregrounded, so a nudge
/// isn't silently swallowed when the user already has the app open.
///
/// Registered as the `UNUserNotificationCenter` delegate from `makeLauncher`'s
/// `initializePrerequisites` rather than ad hoc in the app delegate, so launch
/// wiring lives in one place. The single `shared` instance is retained for the
/// process because the notification center's `delegate` is weak; the type is
/// stateless, hence `@unchecked Sendable`.
final class ForegroundNotificationPresenter:
    NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable
{
    private static let shared = ForegroundNotificationPresenter()

    /// Register the shared presenter as the notification center's delegate.
    /// Idempotent: assigning the same delegate twice is a no-op.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
