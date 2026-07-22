import PeriscopeCore
import SwiftUI
import UserNotifications
import WhereCore

/// The Where app's launch and reset, as **raw async/await** — no lifecycle
/// engine. One task per attempt runs `run` top to bottom; `RootView` renders
/// the app-owned `WhereLaunchState.Phase` it publishes.
///
/// The structure carries the invariants the old engine enforced, now as
/// conventions this file owns:
///
/// - **One store open per process**: `run` reuses `model.services` when a
///   prior attempt (or a preview/test) already assembled the layer —
///   state-check idempotence instead of engine memoization. Nothing re-runs
///   within an attempt because nothing is ever driven twice: promotion is a
///   *park*, not a re-drive.
/// - **The park is the headless/foreground boundary.** A headless launch
///   services the wake (store, session, authorization, tracking, the
///   notification/widget fan) and then simply never proceeds past
///   `whenSceneActive()` — there is no launch-reason enum and no view-tree
///   gating rule to uphold; the foreground tail (onboarding, the one-shot
///   today fix) structurally can't run without a scene. The one ordering the
///   park model must branch on explicitly: session configuration runs
///   *before* the park for a headless-so-far attempt, but *after* the
///   onboarding park when the scene is already active — see `run`.
/// - **A cancelled attempt never writes the phase.** The reset cancels and
///   drains the in-flight attempt (and its fan) before erasing; every phase
///   write below is guarded on cancellation.
/// - **Failure is terminal** (no retry): transiently retryable work belongs
///   to the layer that understands it, and the recovery for anything else is
///   relaunching the app.
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

    /// Compose and kick off the launch: synchronous must-exist-now wiring (a
    /// `WhereBootstrap` installs the `CLLocationManager` so a background
    /// relaunch's queued event isn't lost; the foreground-notification
    /// presenter is registered), then the first attempt task running `run`.
    ///
    /// The attempt runner is retained on the returned state so a reset can
    /// begin a fresh attempt with the same composition. `onServicesReady`
    /// fires on every session (re)start — first launch and each reset
    /// relaunch — handing the service layer to consumers WhereUI can't see
    /// (the App Intents stack; see the app's `AppDelegate`).
    public static func start(
        model: WhereModel,
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> WhereLaunchState {
        let bootstrap = WhereBootstrap()
        bootstrap.prepareLocation()
        ForegroundNotificationPresenter.install()
        logger { .launchStarted }
        let state = WhereLaunchState()
        state.runAttempt = {
            await run(
                model: model,
                bootstrap: bootstrap,
                state: state,
                onServicesReady: onServicesReady,
            )
        }
        state.beginAttempt()
        return state
    }

    /// One launch attempt, top to bottom. Runs on the attempt task
    /// `WhereLaunchState` owns; a reset cancels that task and the phase
    /// guards below keep the superseded attempt from writing over the
    /// reset's state.
    private static func run(
        model: WhereModel,
        bootstrap: WhereBootstrap,
        state: WhereLaunchState,
        onServicesReady: @MainActor (WhereServices) async -> Void,
    ) async {
        do {
            // Open the SwiftData store and assemble the service layer — the
            // process's **one** store open. Reuses already-attached services
            // (a preview/test injected them, or a prior attempt before a
            // reset), so we never spin up a second store + CoreLocation
            // behind a retained layer. Opening may run a lightweight
            // migration; the splash fades in its own launch-neutral caption
            // when any launch phase runs long.
            let services: WhereServices
            if let attached = model.services {
                services = attached
            } else {
                services = try await bootstrap.makeServices()
                model.attach(services: services)
            }

            // Create the logged-in session and hand the service layer to the
            // app's composition hook before anything downstream — or the UI —
            // consumes it, so parked App Intents resume against this
            // session's store.
            let session = model.startSession(services: services)
            await onServicesReady(session.services)

            /// Session configuration runs exactly once per attempt, but *when*
            /// depends on how the attempt meets the scene — the one ordering
            /// the park model must branch on explicitly (the old engine's
            /// run-once memo handled it uniformly):
            ///
            /// - A headless-so-far attempt services the wake NOW — a
            ///   background location relaunch needs tracking reconciled with
            ///   no scene in sight — and then parks.
            /// - An attempt whose scene is already active (a foreground cold
            ///   start, the post-reset relaunch) configures AFTER the
            ///   onboarding park, so a granted-authorization reset can't
            ///   resume GPS into the freshly-erased store while the user is
            ///   still re-onboarding.
            func configureSession() async {
                // Ordered: tracking reconciles against the authorization the
                // sync just read.
                await session.syncAuthorization()
                session.observeAuthorizationChanges()
                await session.seedRegionStyles()
                session.observeRegionStyleChanges()
                await session.reconcileTracking()
                // The configuration fan: concurrent, never blocks readiness;
                // the session methods own their failure handling (they don't
                // throw). A reset drains these before the fresh attempt.
                state.spawnFan { await session.applyReminderConfiguration() }
                state.spawnFan { await session.applySummaryConfiguration() }
                state.spawnFan { await session.applyIssueAlertConfiguration() }
                state.spawnFan { await session.refreshWidgetSnapshot() }
            }

            var wakeServiced = false
            if !state.sceneHasBeenActive {
                await configureSession()
                wakeServiced = true
            }

            // The park: a headless wake is fully serviced above this line and
            // never proceeds past it. Promotion isn't a re-drive — the task
            // just resumes here when a scene becomes active.
            try await state.whenSceneActive()

            // First-run onboarding, parked on a handle the view resolves.
            // The view commits the picked regions and marks `hasOnboarded`
            // before completing.
            if !model.hasOnboarded {
                let handle = OnboardingHandle()
                guard !Task.isCancelled else { return }
                state.publish(.onboarding(handle, session))
                try await handle.waitForCompletion()
            }

            if !wakeServiced {
                await configureSession()
            }

            // Foreground-only: don't spend a one-shot GPS fix on a headless
            // wake (a background relaunch is itself the passive event).
            state.spawnFan { await session.captureTodayIfNeeded() }

            guard !Task.isCancelled else { return }
            state.publish(.ready(session))
        } catch is CancellationError {
            // Superseded by a reset — it owns the phase now.
        } catch {
            guard !Task.isCancelled else { return }
            // Log as well as publish: a headless attempt's failure surface is
            // never rendered, so without this line the failure would leave no
            // trace anywhere.
            logger(attachments: [.error(error, name: "launch-error")]) {
                .launchFailed(description: error.localizedDescription)
            }
            state.publish(.failed(error))
        }
    }

    /// Settings' "Erase all data & reset": cancel and drain the in-flight
    /// attempt (and its fan), wipe the store, drop the session, clear the
    /// preferences that gate the relaunch, then begin a fresh attempt — which,
    /// with `hasOnboarded` now cleared, parks on onboarding again, returning
    /// the app to its first-run state.
    ///
    /// If the erase throws, the launch state parks in `.failed` (terminal —
    /// relaunch the app) with the session and preferences intact, rather than
    /// stranding the user in onboarding atop un-erased data.
    public static func reset(
        model: WhereModel,
        state: WhereLaunchState,
        session: WhereSession,
    ) async {
        await state.cancelAndDrainAttempt()
        state.publish(.launching)
        do {
            try await session.eraseSession()
            model.endSession()
            model.resetPreferences()
            state.beginAttempt()
        } catch {
            logger(attachments: [.error(error, name: "reset-error")]) {
                .resetFailed(description: error.localizedDescription)
            }
            state.publish(.failed(error))
        }
    }
}

/// Owns the launch-time assembly of `WhereServices` so `WhereModel`
/// consumes a finished service layer rather than wiring up persistence and
/// CoreLocation itself.
///
/// `prepareLocation()` runs synchronously from `WhereLaunch.start`,
/// installing the `CLLocationManager` + delegate early so a background
/// relaunch's queued significant-change / visit event is buffered (in
/// `CoreLocationSource.sampleStream`) rather than dropped while the async
/// store open runs. `makeServices()` then opens the store off the main actor
/// and assembles the services from the two.
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
    /// persistence failure so the launch can surface it.
    ///
    /// This is the app process's **one** store open — everything else shares
    /// the instance by injection (the App Intents stack derives from these
    /// services via `WhereServices.forIntents(sharingStoreOf:)`; see the
    /// app's `AppDelegate`), so no second container ever races this one over
    /// the same store file.
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
/// Registered as the `UNUserNotificationCenter` delegate from
/// `WhereLaunch.start` rather than ad hoc in the app delegate, so launch
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
