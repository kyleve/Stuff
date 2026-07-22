import LifecycleKit
import PeriscopeCore
import SwiftUI
import UserNotifications
import WhereCore

/// Stable identifiers for the steps in `WhereLaunch.launch(for:)` and
/// `reset(for:)`. Raw strings drift silently (a typo just creates a new,
/// untracked step); an enum makes each ID a compile-checked symbol and gives
/// the launch/reset parity tests a single source of truth.
public enum LaunchStepID: String {
    /// Open the SwiftData store and assemble the services — the trunk's
    /// store scope. The splash's slow-launch caption most often shows here.
    case openStore = "open-store"
    /// Build the logged-in session over the services and fire the app's
    /// composition hook — promotes the trunk to the session scope.
    case startSession = "start-session"
    /// First-run onboarding gate. Foreground-only, so a headless launch (an
    /// unpromoted `.undetermined` cold launch or a `.background` relaunch)
    /// skips it — it re-evaluates once a scene promotes the launch.
    case onboarding
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

    /// Reset teardown: stop GPS, wipe the store, and drop the session.
    case eraseData = "erase-data"
    /// Reset teardown: clear the persisted preferences that gate the relaunch
    /// (onboarding flag, tracking intent, reminder/summary schedules).
    case resetPreferences = "reset-preferences"
}

/// Assembles the Where app's cold-launch function and the `LifecycleRunner`
/// that drives it.
///
/// The launch is only the *prerequisites*; the destination — the real tab UI
/// — is `LifecycleContainer`'s `content` (see `RootView`), handed the
/// `WhereSession` the function returned once the runner reaches `.ready`.
///
/// The function is ordinary async Swift: its `let`s are the launch's
/// dependency scope, growing monotonically by embedding — the `open-store`
/// step mints `WhereServices` (the store scope), `start-session` promotes it
/// to `WhereSession` (which carries the services non-optionally), and every
/// downstream step closes over the session. The compiler holds the ordering
/// (a value can't be used before the step that produced it), and only `Void`
/// work can be mode-gated, so a skipped step can't leave a hole in the data
/// flow. The one discipline the style demands: **all effects live inside
/// `context.step`/`gate`/`detached`** — bare glue between steps re-runs on
/// every re-drive (promotion, retry).
@MainActor
public enum WhereLaunch {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    /// How much log history the on-disk store keeps: 100 days. Older events are
    /// pruned at launch so the database can't grow without bound. (A size cap to
    /// bound heavy-logging devices within the window is tracked in `Where/TODOs.md`.)
    private static let logRetention: TimeInterval = 100 * 24 * 60 * 60

    /// Open the process-global Periscope store, attach it to `Periscope.shared`
    /// as the durable sink, start the built-in ambient sources, and prune
    /// history past `logRetention` — then hand the store to `model` so the DEBUG
    /// developer surface can browse it.
    ///
    /// Runs off the launch critical path on its own task: opening the store
    /// touches disk (and may run a lightweight migration), which must not block
    /// `didFinishLaunching`. The OSLog sink already installed on
    /// `Periscope.shared` covers the pre-attach window, and `add(sink:)` replays
    /// every scope defined so far so the store resolves the records it sees.
    /// (Fully closing that pre-attach window — a bootstrap journal from process
    /// start — is tracked as a P0 in `Shared/Periscope/TODOs.md`.)
    ///
    /// Once the store is attached the developer surface can browse it
    /// immediately: `.loggingStoreReady` fires right after `add(sink:)`, and
    /// retention pruning runs *after* that on its own task, since trimming old
    /// history isn't a readiness prerequisite.
    ///
    /// Degraded-but-handled on failure: if the store can't open, logging keeps
    /// flowing through OSLog and the failure is recorded (with the error
    /// attached) rather than crashing a launch over diagnostics.
    ///
    /// Called once from the app delegate at process launch.
    public static func bootstrapLogging(model: WhereModel) {
        Task {
            let store: PeriscopeStore
            do {
                store = try await PeriscopeStore.make(storage: .onDisk, session: .current())
            } catch {
                logger(attachments: [.error(error, name: "open-error")]) {
                    .loggingStoreUnavailable(description: String(describing: error))
                }
                return
            }
            Periscope.shared.add(sink: store)
            Periscope.shared.startDefaultAmbientSources()
            model.attach(logStore: store)
            logger { .loggingStoreReady }
            pruneHistory(in: store)
        }
    }

    /// Trim log history past `logRetention` on its own task, so it never delays
    /// `.loggingStoreReady`. The actual prune runs on the store actor (off the
    /// main thread); a failure is degraded-but-handled — the store keeps its
    /// last good history and stays usable, it just isn't trimmed this launch.
    private static func pruneHistory(in store: PeriscopeStore) {
        Task {
            do {
                let cutoff = Date().addingTimeInterval(-logRetention)
                let pruned = try await store.pruneEvents(olderThan: cutoff)
                logger { .historyPruned(prunedEventCount: pruned) }
            } catch {
                logger(attachments: [.error(error, name: "prune-error")]) {
                    .historyPruneFailed(description: String(describing: error))
                }
            }
        }
    }

    /// Build the runner for `model`, launching for `reason`.
    ///
    /// `initializePrerequisites` runs the synchronous, must-exist-now launch
    /// wiring before any async node: a `WhereBootstrap` installs the
    /// `CLLocationManager` (`prepareLocation()`) so a background relaunch's
    /// queued event isn't lost while the async `open-store` step assembles the
    /// services, and the foreground-notification presenter is registered so a
    /// reminder fired while Where is open still shows. Keeping both here (rather
    /// than in the app delegate) puts app-lifecycle wiring in one place.
    ///
    /// `onServicesReady` fires from the `start-session` step every time a
    /// session is (re)started over the assembled services — first launch, a
    /// retry after a failed launch, and the reset relaunch. The app uses it to
    /// hand the service layer to consumers WhereUI can't see (deriving and
    /// installing the App Intents stack — see the app's `AppDelegate`);
    /// previews and tests omit it.
    public static func makeLauncher(
        model: WhereModel,
        reason: LifecycleReason,
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> LifecycleRunner<WhereSession> {
        let bootstrap = WhereBootstrap()
        logger { .runnerCreated(reason: String(describing: reason)) }
        let runner = LifecycleRunner(
            reason: reason,
            initializePrerequisites: {
                bootstrap.prepareLocation()
                ForegroundNotificationPresenter.install()
            },
            launch: launch(
                for: model,
                bootstrap: bootstrap,
                onServicesReady: onServicesReady,
            ),
        )
        // Mirror detached-step failures into WhereLog: the runner only
        // records them on its observable `detachedFailures`, which nothing
        // renders — without this a throwing detached step would fail with no
        // trace in logs.
        DetachedFailureReporter.observe(runner)
        return runner
    }

    /// The launch function. The required steps mirror the imperative
    /// `WhereSession.start()` order (a parity test on the runner's executed
    /// IDs guards this); the only insertions are the `start-session` scope
    /// promotion and the `onboarding` gate, neither of which `start()`
    /// models. The independent session-configuration steps fan out detached
    /// after the trunk — they close over the session, return nothing, and
    /// never block `.ready`.
    ///
    /// `bootstrap` assembles the services in the `open-store` step, and
    /// `onServicesReady` fires from `start-session` whenever a session is
    /// (re)started (see `makeLauncher`); previews and tests can rely on the
    /// defaults.
    public static func launch(
        for model: WhereModel,
        bootstrap: WhereBootstrap = WhereBootstrap(),
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> @MainActor (LifecycleContext) async throws -> WhereSession {
        { context in
            // Open the SwiftData store and assemble the service layer — the
            // process's **one** store open (everything else shares the
            // instance by injection; see `WhereBootstrap.makeServices`).
            // Reuses already-attached services (a preview/test injected them,
            // or a prior session before a reset), so we never spin up a real
            // store + CoreLocation behind a retained layer. Opening may run a
            // lightweight migration; there's no separate UI for it — the
            // launch splash fades in its own launch-neutral caption when any
            // launch phase runs long.
            let services: WhereServices = try await context.step(LaunchStepID.openStore) {
                if let services = model.services { return services }
                let services = try await bootstrap.makeServices()
                model.attach(services: services)
                return services
            }

            // Create the logged-in session and hand the service layer to the
            // app's composition hook before any later step — or the UI —
            // runs, so consumers awaiting it (parked App Intents) resume
            // against this session's store. Runs on every session (re)start:
            // first launch, a retry after a failed open, and the reset
            // relaunch (whose fresh attempt clears the run-once memo).
            let session: WhereSession = try await context.step(LaunchStepID.startSession) {
                let session = model.startSession(services: services)
                await onServicesReady(session.services)
                return session
            }

            // First-run onboarding. The gate is foreground-only, so a
            // headless launch skips it unmemoized — and this plain `if`
            // re-evaluates when a scene promotes the launch and the function
            // re-runs, so a cold `.undetermined` start still onboards once
            // it becomes user-visible. `RootView` registers `OnboardingView`
            // for the gate type; the view receives the session passed here.
            if !model.hasOnboarded {
                try await context.gate(OnboardingGate(), value: session)
            }

            // Read location authorization into the coordinator and start
            // observing live authorization + region-style changes. Required
            // and ordered: the reconcile step below must see the synced
            // authorization.
            try await context.step(LaunchStepID.syncAuth) {
                await session.syncAuthorization()
                session.observeAuthorizationChanges()
                await session.seedRegionStyles()
                session.observeRegionStyleChanges()
            }

            // Start or stop GPS ingestion to match the user's intent + the
            // authorization the previous step just synced.
            try await context.step(LaunchStepID.reconcileTracking) {
                await session.reconcileTracking()
            }

            // The independent session-configuration fan: fire-and-forget,
            // never blocks `.ready`, failures surface on `detachedFailures`
            // (mirrored into WhereLog by `DetachedFailureReporter`).
            //
            // Capture-today is foreground-only — a headless launch shouldn't
            // spend a fresh one-shot GPS fix (a `.background` relaunch is
            // itself the passive event); it runs once a scene promotes the
            // launch and the function re-runs.
            context.detached(LaunchStepID.captureToday, modes: .foreground) {
                await session.captureTodayIfNeeded()
            }
            // Push the logging-reminder schedule + badge to the reconciler.
            context.detached(LaunchStepID.reminders) {
                await session.applyReminderConfiguration()
            }
            // Push the daily-summary recap to the reconciler.
            context.detached(LaunchStepID.summary) {
                await session.applySummaryConfiguration()
            }
            // Push the "issues to resolve" notification intent to its
            // reconciler.
            context.detached(LaunchStepID.issueAlerts) {
                await session.applyIssueAlertConfiguration()
            }
            // Republish the widget snapshot from whatever is already on disk,
            // so a cold launch with no writes this session doesn't leave the
            // widget blank or showing the previous day's "today".
            context.detached(LaunchStepID.widgetSnapshot) {
                await session.refreshWidgetSnapshot()
            }

            return session
        }
    }

    /// The reverse of `launch(for:)`: the teardown run by Settings' "Erase
    /// all data & reset", rooted at the session being torn down (Settings
    /// hands it in as the teardown input — no optional re-read).
    /// `LifecycleRunner.teardown` runs it, then re-runs the launch function
    /// as a fresh attempt — which, with `hasOnboarded` now cleared, parks on
    /// the onboarding gate again, returning the app to its first-run state.
    public static func reset(
        for model: WhereModel,
    ) -> @MainActor (WhereSession, LifecycleContext) async throws -> Void {
        { session, context in
            // Stop GPS and wipe the store first, then drop the session. If
            // the erase throws the runner parks in `.failed` with the session
            // and preferences intact, so a retry re-erases rather than
            // stranding the user in onboarding atop un-erased data. Dropping
            // the session makes the relaunch rebuild a fresh one over the
            // erased store (the services stay retained).
            try await context.step(LaunchStepID.eraseData) {
                try await session.eraseSession()
                model.endSession()
            }
            // Clear the persisted preferences that gate the relaunch
            // (onboarding flag, tracking intent, reminder/summary schedules),
            // so the next launch behaves like a fresh install.
            try await context.step(LaunchStepID.resetPreferences) {
                model.resetPreferences()
            }
        }
    }
}

/// First-run onboarding's gate type: how the launch function parks for the
/// user, and the key `RootView`'s registry maps to `OnboardingView`. Carries
/// no behavior — conditionality is the `if !model.hasOnboarded` at the call
/// site; `Value` is the session the gate view commits regions with.
struct OnboardingGate: LifecycleGate {
    typealias Value = WhereSession

    let id: AnyHashable = LaunchStepID.onboarding
}

/// Owns the launch-time assembly of `WhereServices` so `WhereModel`
/// consumes a finished service layer rather than wiring up persistence and
/// CoreLocation itself.
///
/// `prepareLocation()` runs synchronously as the runner's
/// `initializePrerequisites`, installing the `CLLocationManager` + delegate
/// early so a background relaunch's queued significant-change / visit event is
/// buffered (in `CoreLocationSource.sampleStream`) rather than dropped while
/// the async `open-store` step runs. `makeServices()` then opens the store
/// off the main actor and assembles the services from the two.
@MainActor
public final class WhereBootstrap {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    private var locationSource: CoreLocationSource?

    public init() {}

    /// Install the `CLLocationManager` + delegate right away, without touching
    /// the store. Idempotent.
    public func prepareLocation() {
        guard locationSource == nil else { return }
        locationSource = CoreLocationSource()
    }

    /// Open the SwiftData store (on a detached task so a slow open or first
    /// creation runs off the main actor the splash renders on) and assemble
    /// the services from it and the prepared location source. Throws on
    /// persistence failure so the `open-store` step can surface it.
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
            let store = try await Task.detached(priority: .userInitiated) {
                try SwiftDataStore.make()
            }.value
            let services = try await WhereServices.make(
                store: store,
                locationSource: source,
                locationOutbox: FileLocationOutbox.applicationSupport(),
            )
            Self.logger { .servicesAssembled }
            return services
        } catch {
            Self.logger(attachments: [.error(error, name: "assemble-error")]) {
                .servicesAssemblyFailed(description: error.localizedDescription)
            }
            throw error
        }
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
