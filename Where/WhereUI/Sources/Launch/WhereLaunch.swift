import LifecycleKit
import LogKit
import SwiftUI
import UserNotifications
import WhereCore

/// Stable identifiers for the steps in `WhereLaunch.sequence` and
/// `resetSequence`. Raw strings drift silently (a typo just creates a new,
/// untracked step); an enum makes each ID a compile-checked symbol and gives
/// the launch/reset parity tests a single source of truth.
public enum LaunchStepID: String {
    /// Open the SwiftData store, assemble the services, and build the session.
    /// The splash's slow-launch caption most often shows during this step.
    case openStore = "open-store"
    /// First-run onboarding gate. Foreground-only, so a headless launch (an
    /// unpromoted `.undetermined` cold launch or a `.background` relaunch) skips
    /// it — it runs only once a scene promotes the launch to foreground.
    case onboarding
    /// Read location authorization into the coordinator and start observing live
    /// authorization changes. The report + data-issue scan (and their
    /// store-change subscription) load with the scene now, not here — so a
    /// headless launch (no scene) never drives a refresh no UI consumes.
    case syncAuth = "sync-auth"
    /// Start or stop GPS ingestion to match the user's intent + authorization.
    case reconcileTracking = "reconcile-tracking"
    /// Take a one-shot GPS fix for today if none is logged yet, so opening the
    /// app on a fresh day fills the calendar in. Foreground-only — a headless
    /// launch shouldn't spend a fresh fix (a `.background` relaunch is itself the
    /// passive event); it runs once a scene promotes the launch.
    case captureToday = "capture-today"
    /// Push the logging-reminder schedule + badge (backlog + issue count) to the
    /// reconciler.
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

/// Assembles the Where app's cold-launch sequence and the `LifecycleRunner`
/// that drives it.
///
/// The sequence is only the *prerequisites*; the destination — the real tab UI
/// — is `LifecycleContainer`'s `content` (see `RootView`), shown once the
/// runner reaches `.ready`. It mirrors the imperative `WhereSession.start()`:
/// CoreLocation is wired synchronously in `initializePrerequisites`, then the
/// store opens, the session is built, and the rest of the work runs as ordered
/// async steps.
@MainActor
public enum WhereLaunch {
    private static let logger = WhereLog.channel(.launch)

    /// Build the runner for `model`, launching for `reason`.
    ///
    /// `initializePrerequisites` runs the synchronous, must-exist-now launch
    /// wiring before any async step: a `WhereBootstrap` installs the
    /// `CLLocationManager` (`prepareLocation()`) so a background relaunch's
    /// queued event isn't lost while the async `open-store` step assembles the
    /// services, and the foreground-notification presenter is registered so a
    /// reminder fired while Where is open still shows. Keeping both here (rather
    /// than in the app delegate) puts app-lifecycle wiring in one place.
    ///
    /// `onServicesReady` fires from the `open-store` step every time a session
    /// is (re)started over the assembled services — first launch, a retry
    /// after a failed launch, and the reset relaunch. The app uses it to hand
    /// the service layer to consumers WhereUI can't see (deriving and
    /// installing the App Intents stack — see the app's `AppDelegate`);
    /// previews and tests omit it.
    public static func makeLauncher(
        model: WhereModel,
        reason: LifecycleReason,
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> LifecycleRunner {
        let bootstrap = WhereBootstrap()
        logger.info("Lifecycle runner created (reason: \(reason))")
        return LifecycleRunner(
            reason: reason,
            initializePrerequisites: {
                bootstrap.prepareLocation()
                ForegroundNotificationPresenter.install()
            },
            sequence: sequence(
                for: model,
                bootstrap: bootstrap,
                onServicesReady: onServicesReady,
            ),
        )
    }

    /// The ordered launch steps. The work steps run in the same order as
    /// `WhereSession.start()` (a parity test guards this); the only additions
    /// are the foreground-only `open-store` presentation and the `onboarding`
    /// gate, neither of which `start()` models.
    ///
    /// `bootstrap` assembles the services in the `open-store` step, and
    /// `onServicesReady` fires there whenever a session is (re)started (see
    /// `makeLauncher`); callers that only inspect the step list (the parity
    /// test) can rely on the defaults.
    public static func sequence(
        for model: WhereModel,
        bootstrap: WhereBootstrap = WhereBootstrap(),
        onServicesReady: @escaping @MainActor (WhereServices) async -> Void = { _ in },
    ) -> LifecycleSteps {
        LifecycleSteps {
            // Open the store, assemble the services, and create the session.
            // The build is skipped when services are already retained (a
            // preview/test injected them, or a prior session before a reset) so
            // we never spin up a real store + CoreLocation behind it; the
            // session is then (re)created from the retained layer. Opening may
            // run a lightweight migration; there's no separate UI for it — the
            // launch splash (shown throughout) fades in its own launch-neutral
            // "taking a moment" caption when any launch phase runs long.
            LifecycleStep.work(LaunchStepID.openStore) { _ in
                guard model.session == nil else { return }
                if !model.hasServices {
                    try await model.attach(services: bootstrap.makeServices())
                }
                model.startSession()
                // Hand the (re)started session's service layer to the app's
                // composition hook before any later step — or the UI — runs,
                // so consumers awaiting it (parked App Intents) resume against
                // this session's store.
                if let session = model.session {
                    await onServicesReady(session.services)
                }
            }

            // First run only. `LifecycleStep.interactive` defaults to
            // `modes: .foreground`, so a headless launch (unpromoted
            // `.undetermined`, or a `.background` relaunch) skips it (and never
            // deadlocks waiting for a tap that can't come).
            LifecycleStep.interactive(
                LaunchStepID.onboarding,
                condition: { !model.hasOnboarded },
            ) { OnboardingView(bridge: $0) }

            LifecycleStep.work(LaunchStepID.syncAuth) { _ in
                await model.session?.syncAuthorization()
                model.session?.observeAuthorizationChanges()
            }
            LifecycleStep.work(LaunchStepID.reconcileTracking) { _ in
                await model.session?.reconcileTracking()
            }
            // Foreground-only: a headless launch shouldn't trigger a fresh
            // foreground fix (a `.background` relaunch is itself the passive
            // location event), so it runs only once a scene promotes the launch.
            // Returns fast (the ingestor spawns the ~10s fix internally), so it
            // never delays reaching `.ready`.
            LifecycleStep.work(LaunchStepID.captureToday, modes: .foreground) { _ in
                await model.session?.captureTodayIfNeeded()
            }
            LifecycleStep.work(LaunchStepID.reminders) { _ in
                await model.session?.applyReminderConfiguration()
            }
            LifecycleStep.work(LaunchStepID.summary) { _ in
                await model.session?.applySummaryConfiguration()
            }
            LifecycleStep.work(LaunchStepID.issueAlerts) { _ in
                await model.session?.applyIssueAlertConfiguration()
            }
            LifecycleStep.work(LaunchStepID.widgetSnapshot) { _ in
                await model.session?.refreshWidgetSnapshot()
            }
        }
    }

    /// The reverse of `sequence`: the teardown run by Settings' "Erase all data
    /// & reset". `LifecycleRunner.teardown` runs these steps, then re-drives
    /// `sequence` from the top — which, with `hasOnboarded` now cleared, lands
    /// back on the onboarding step, returning the app to its first-run state.
    public static func resetSequence(for model: WhereModel) -> LifecycleSteps {
        LifecycleSteps {
            // Stop GPS and wipe the store first, then drop the session and clear
            // the preferences that gate the relaunch (onboarding, tracking
            // intent, reminders). If the erase throws the runner parks in
            // `.failed`, the session and preferences are left intact, so a retry
            // re-erases rather than stranding the user in onboarding atop
            // un-erased data. Dropping the session here makes the re-driven
            // `sequence` rebuild a fresh one over the erased store.
            LifecycleStep.work(LaunchStepID.eraseData) { _ in
                try await model.eraseAllData()
                model.endSession()
            }
            LifecycleStep
                .work(LaunchStepID.resetPreferences) { _ in model.resetPreferences() }
        }
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
    private static let logger = WhereLog.channel(.launch)

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
            Self.logger.info("WhereServices assembled")
            return services
        } catch {
            Self.logger.error(
                "Failed to assemble WhereServices: \(error.localizedDescription)",
            )
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
