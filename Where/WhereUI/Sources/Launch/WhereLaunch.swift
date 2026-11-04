import LifecycleKit
import Observation
import PeriscopeCore
import SwiftUI
import UserNotifications
import WhereCore

/// Stable identifiers for the nodes in `WhereLaunch.plan(for:)` and
/// `resetPlan(for:)`. Raw strings drift silently (a typo just creates a new,
/// untracked step); an enum makes each ID a compile-checked symbol and gives
/// the launch/reset parity tests a single source of truth.
public enum LaunchStepID: String, Sendable {
    /// Consume an optional one-shot demo request before onboarding can open a real store.
    case activateDemo = "activate-demo"
    /// Resolve device-local identity before onboarding or a real store can use it.
    case resolveInstallation = "resolve-installation"
    /// First-run onboarding gate, after optional demo activation: until the user
    /// chooses a world to work in, nothing downstream runs and no store is
    /// opened. Applies to every launch reason — a headless launch parks here
    /// rather than opening the user's store unseen.
    case onboarding
    case compatibility
    case suspendCompatibility = "suspend-compatibility"
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
/// The trunk consumes an optional one-shot demo request, then reaches the
/// onboarding gate — nothing real may be built until the user has chosen a
/// world to work in — and its value then grows monotonically
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
        WhereCompatibilityLifecycle.observe(runner: runner, model: model)
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
    /// Keeping the gate ahead of real scope resolution is what makes the app's store open *lazily*:
    /// a user
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
        LaunchPlan(ActivateLaunchDemoStep(model: model).measured())
            .then(ResolveInstallationContextStep(model: model).measured())
            .gate(DataCompatibilityGate(model: model))
            .gate(OnboardingGate(model: model))
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
    /// Production returns its retained dataset coordinator. Isolated fixtures explicitly return
    /// nil.
    func prepareDataCompatibility() throws -> DataCompatibilityCoordinator?

    /// Drain current services or remove previous-process output before a blocked launch continues.
    func withdrawHistoryOutputs() async

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
@Observable
public final class WhereBootstrap: WhereScopeAssembling {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    private let installationContextStore: any InstallationRecordingContextStoring
    private let storeStorage: SwiftDataStore.Storage
    private let dataset: DataCompatibilityDataset
    private let widgetRefresher: any WidgetTimelineRefreshing
    private let locationOutbox: any LocationOutbox
    private var locationSource: (any LocationSource)?
    private var dataCompatibility: DataCompatibilityCoordinator?
    private var currentServices: WhereServices?
    private var outputWithdrawal: Task<Void, Never>?

    /// Fixed at construction; the testing initializer supplies isolated protocol adapters.
    @MainActor
    private struct PlatformAdapters {
        let makeLocationSource: @MainActor () -> any LocationSource
        let imports: any CloudKitImportReadying
        let reminders: any LoggingReminderScheduling
        let summary: any DailySummaryScheduling
        let issues: any DataIssueAlertScheduling

        static var live: Self {
            Self(
                makeLocationSource: { CoreLocationSource() },
                imports: CloudKitImportReadiness(),
                reminders: UserNotificationReminderScheduler(),
                summary: UserNotificationDailySummaryScheduler(),
                issues: UserNotificationDataIssueAlertScheduler(),
            )
        }
    }

    private var adapters = PlatformAdapters.live

    public init(
        installationContextStore: any InstallationRecordingContextStoring,
        storeStorage: SwiftDataStore.Storage,
        dataset: DataCompatibilityDataset,
        widgetRefresher: any WidgetTimelineRefreshing,
        locationOutbox: any LocationOutbox,
    ) {
        self.installationContextStore = installationContextStore
        self.storeStorage = storeStorage
        self.dataset = dataset
        self.widgetRefresher = widgetRefresher
        self.locationOutbox = locationOutbox
    }

    @_spi(Testing)
    public convenience init(
        installationContextStore: any InstallationRecordingContextStoring,
        storeStorage: SwiftDataStore.Storage,
        coordinator: DataCompatibilityCoordinator,
        makeLocationSource: @escaping @MainActor () -> any LocationSource,
        importReadiness: any CloudKitImportReadying,
        widgetRefresher: any WidgetTimelineRefreshing,
        locationOutbox: any LocationOutbox,
    ) {
        self.init(
            installationContextStore: installationContextStore,
            storeStorage: storeStorage,
            dataset: .local(.init(rawValue: "bootstrap-fixture")),
            widgetRefresher: widgetRefresher,
            locationOutbox: locationOutbox,
        )
        dataCompatibility = coordinator
        adapters = PlatformAdapters(
            makeLocationSource: makeLocationSource,
            imports: importReadiness,
            reminders: NoopLoggingReminderScheduler(),
            summary: NoopDailySummaryScheduler(),
            issues: NoopDataIssueAlertScheduler(),
        )
    }

    /// Install the `CLLocationManager` + delegate right away, without touching
    /// the store. Idempotent.
    public func prepareLocation() {
        guard locationSource == nil else { return }
        locationSource = adapters.makeLocationSource()
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
        let source = locationSource ?? adapters.makeLocationSource()
        locationSource = nil
        do {
            let installationContext = try installationContextStore.resolve()
            precondition(
                installationContext.automaticRecordingEnabled != nil,
                "A real scope cannot open before this installation confirms recording.",
            )
            await outputWithdrawal?.value
            if let currentServices { await currentServices.retireCompatibilityScope() }
            let access = try await admittedAccess()
            let services = try await WhereServices.make(
                access: access,
                locationSource: source,
                installationContext: installationContext,
                aggregator: DayAggregator(),
                // The real world's seams, named here because this is the only
                // place that wants them: the demo scope builds the same stack
                // out of no-ops, and every test and preview gets no-ops by
                // default.
                reminderScheduler: adapters.reminders,
                summaryScheduler: adapters.summary,
                issueAlertScheduler: adapters.issues,
                widgetRefresher: widgetRefresher,
                locationOutbox: locationOutbox,
                importRecoveryPersistence: installationContextStore,
                now: Date.init,
            )
            await outputWithdrawal?.value
            try services.validateDataAccess()
            currentServices = services
            Self.logger.servicesAssembled()
            return services
        } catch {
            await source.stop()
            Self.logger.servicesAssemblyFailed(
                error: .restricted(.errorDetails, error),
            )
            throw error
        }
    }

    public func discoverRecordingDevices() async throws -> [RecordingDevice] {
        let access = try await admittedAccess()
        if storeStorage.usesCloudKit, await adapters.imports.waitForImport() == false {
            throw CloudKitImportReadiness.Timeout()
        }
        return try await access.store.recordingDevices()
    }

    private func admittedAccess() async throws -> DataCompatibilityAccess {
        let coordinator = try prepareCoordinator()
        if let access = coordinator.access, !access.isRevoked { return access }
        return try await coordinator.refresh()
    }

    public func prepareDataCompatibility() throws -> DataCompatibilityCoordinator? {
        try prepareCoordinator()
    }

    private func prepareCoordinator() throws -> DataCompatibilityCoordinator {
        // Admission can open the mirror before discovery runs. Observe its first import now,
        // retaining the result until discovery asks for it.
        if storeStorage.usesCloudKit { adapters.imports.start() }
        if let dataCompatibility { return dataCompatibility }
        let hasExistingHistory: Bool
        switch storeStorage {
            case .inMemory: hasExistingHistory = false
            case let .localOnly(appGroupIdentifier), let .cloudKit(appGroupIdentifier):
                guard let group = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: appGroupIdentifier,
                ) else { throw WidgetSnapshotStore.AppGroupUnavailableError() }
                do {
                    hasExistingHistory = try SwiftDataStore
                        .inspectorStoreURL(groupContainerURL: group).checkResourceIsReachable()
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    hasExistingHistory = false
                }
        }
        let storeStorage = storeStorage
        let preparation = DataCompatibilityStorePreparation(
            hasExistingHistory: hasExistingHistory,
            makeStore: {
                try await Task.detached(priority: .userInitiated) {
                    try SwiftDataStore.make(storage: storeStorage)
                }.value
            },
        )
        let source: DataCompatibilityCoordinator.Source
        switch dataset {
            case let .local(storeID): source = .local(storeID: storeID)
            case let .cloudKit(storeID, containerIdentifier):
                let directory = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false,
                ).appending(path: "WhereDataCompatibility", directoryHint: .isDirectory)
                source = .cloudKit(
                    storeID: storeID,
                    transport: CloudKitDataCompatibilityTransport(
                        containerIdentifier: containerIdentifier,
                    ),
                    cache: FileDataCompatibilityCache(fileURL: directory
                        .appending(path: "account.json")),
                )
        }
        let coordinator = DataCompatibilityCoordinator(
            storePreparation: preparation,
            source: source,
            policy: .foundation,
            activationReadiness: .pendingValidation,
        )
        coordinator.startObserving()
        dataCompatibility = coordinator
        return coordinator
    }

    public func withdrawHistoryOutputs() async {
        if let outputWithdrawal { await outputWithdrawal.value; return }
        let services = currentServices
        let widgets = widgetRefresher
        let preparedSource = locationSource
        locationSource = nil
        let adapters = adapters
        let task = Task {
            // Monitoring survives process termination. Stop and discard a prepared source even
            // when cold admission fails before services exist; only the durable outbox survives.
            await preparedSource?.stop()
            if let services {
                await services.retireCompatibilityScope()
            } else {
                await DataCompatibilityOutputs.withdraw(
                    reminders: adapters.reminders,
                    summary: adapters.summary,
                    issues: adapters.issues,
                    widgets: widgets,
                )
            }
        }
        outputWithdrawal = task
        await task.value
        outputWithdrawal = nil
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
