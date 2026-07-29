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

/// Assembles the Where app's cold-launch plan and the `LifecycleRunner` that
/// drives it.
///
/// The plan is only the *prerequisites*; the destination — the real tab UI —
/// is `LifecycleContainer`'s `content` (see `RootView`), handed the
/// `WhereSession` the trunk produced once the runner reaches `.ready`.
///
/// The trunk's value is the launch's dependency scope, growing monotonically
/// by embedding: `OpenStoreStep` mints `WhereServices` (the store scope),
/// `StartSessionStep` promotes it to `WhereSession` (which carries the
/// services non-optionally), and every downstream node takes the session as
/// its typed input. The compiler holds the ordering — a node cannot be
/// placed before its input exists, and only pass-through nodes (the
/// onboarding gate, `thenKeeping` steps, the detached fan) may skip, so a
/// skipped node can't leave a hole in the data flow.
@MainActor
public enum WhereLaunch {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    /// Trims the on-disk log store to ``LogHistoryPruner/Policy/standard`` at
    /// launch — an age window *and* an event ceiling, so the database is bounded
    /// whichever way this install logs.
    private static let historyPruner = LogHistoryPruner(
        policy: .standard,
        now: { Date() },
    )

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
    /// The bring-up is itself a span (`openLogStore`), deliberately ending
    /// *after* `add(sink:)` rather than around the open alone: a span that
    /// closes before the store is a sink records nowhere but OSLog and
    /// Instruments. Its `SpanBegan` is still lost for that same reason — the
    /// pre-attach gap noted below — so the persisted history holds the end (and
    /// with it the duration) without a matching begin, which is what the span
    /// history reads anyway.
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
                store = try await logger.measure(.openLogStore, budget: .seconds(1)) {
                    let store = try await PeriscopeStore.make(
                        storage: .onDisk,
                        session: .current(),
                    )
                    Periscope.shared.add(sink: store)
                    Periscope.shared.startDefaultAmbientSources()
                    return store
                }
            } catch {
                logger(attachments: [.error(error, name: "open-error")]) {
                    .loggingStoreUnavailable(description: String(describing: error))
                }
                return
            }
            model.attach(logStore: store)
            logger { .loggingStoreReady }
            pruneHistory(in: store)
        }
    }

    /// Trim log history to the retention policy on its own task, so it never
    /// delays `.loggingStoreReady`. The actual prune runs on the store actor (off
    /// the main thread); a failure is degraded-but-handled — the store keeps its
    /// last good history and stays usable, it just isn't trimmed this launch.
    private static func pruneHistory(in store: PeriscopeStore) {
        Task {
            do {
                let pruned = try await logger.measure(.pruneHistory, budget: .seconds(2)) {
                    try await historyPruner.prune(store)
                }
                logger {
                    .historyPruned(
                        expiredEventCount: pruned.expired,
                        overflowEventCount: pruned.overflowed,
                    )
                }
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
    /// session is (re)started over the assembled services — first launch, the
    /// fresh process after a failed (terminal) launch, and the in-process reset
    /// relaunch. The app uses it to
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
            plan: plan(
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

    /// The typed launch plan. The trunk mirrors the imperative
    /// `WhereSession.start()` order (a parity test guards this); the only
    /// insertions are the `start-session` scope promotion and the
    /// `onboarding` gate, neither of which `start()` models. The independent
    /// session-configuration steps fan out detached after the trunk — they
    /// take the session, return nothing, and never block `.ready`.
    ///
    /// Every step is composed `.measured()`, so each run is a budgeted
    /// Periscope span named after the step (see `MeasuredStep`) and a slow
    /// launch attributes to a step rather than to "launch". The onboarding gate
    /// is not measured: it parks on the user, so its duration is a human's, not
    /// the app's.
    ///
    /// `bootstrap` assembles the services in the `open-store` step, and
    /// `onServicesReady` fires from `start-session` whenever a session is
    /// (re)started (see `makeLauncher`); callers that only inspect the node
    /// list (the parity test) can rely on the defaults.
    public static func plan(
        for model: WhereModel,
        bootstrap: WhereBootstrap = WhereBootstrap(),
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> LaunchPlan<LaunchStepID, Void, WhereSession> {
        LaunchPlan(OpenStoreStep(model: model, bootstrap: bootstrap).measured())
            .then(StartSessionStep(model: model, onServicesReady: onServicesReady).measured())
            .gate(OnboardingGate(model: model))
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
