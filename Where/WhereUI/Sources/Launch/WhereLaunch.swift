import LifecycleKit
import SwiftUI
import WhereCore

/// Stable identifiers for the steps in `WhereLaunch.sequence` and
/// `resetSequence`. Raw strings drift silently (a typo just creates a new,
/// untracked step); an enum makes each ID a compile-checked symbol and gives
/// the launch/reset parity tests a single source of truth.
public enum LaunchStepID: String {
    /// Open the SwiftData store, assemble the services, and build the session.
    /// The foreground-only migration UI hangs off this step.
    case openStore = "open-store"
    /// First-run onboarding gate. Foreground-only, so a headless background
    /// relaunch skips it.
    case onboarding
    /// Read location authorization into the session and start observing live
    /// changes.
    case syncAuth = "sync-auth"
    /// Start or stop GPS ingestion to match the user's intent + authorization.
    case reconcileTracking = "reconcile-tracking"
    /// Load the selected year's report into the session.
    case loadYear = "load-year"
    /// Push the logging-reminder schedule + backlog badge to the reconciler.
    case reminders
    /// Push the daily-summary recap to the reconciler.
    case summary
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
    /// Build the runner for `model`, launching for `reason`.
    ///
    /// A `WhereBootstrap` owns the services' assembly: its
    /// `prepareLocation()` runs as the runner's `initializePrerequisites`,
    /// installing the `CLLocationManager` synchronously so a background
    /// relaunch's queued event isn't lost while the async `open-store` step
    /// opens the store and assembles the services.
    public static func makeLauncher(model: WhereModel, reason: LifecycleReason) -> LifecycleRunner {
        let bootstrap = WhereBootstrap()
        return LifecycleRunner(
            reason: reason,
            initializePrerequisites: { bootstrap.prepareLocation() },
            sequence: sequence(for: model, bootstrap: bootstrap),
        )
    }

    /// The ordered launch steps. The work steps run in the same order as
    /// `WhereSession.start()` (a parity test guards this); the only additions
    /// are the foreground-only `open-store` presentation and the `onboarding`
    /// gate, neither of which `start()` models.
    ///
    /// `bootstrap` assembles the services in the `open-store` step; callers
    /// that only inspect the step list (the parity test) can rely on the
    /// default.
    public static func sequence(
        for model: WhereModel,
        bootstrap: WhereBootstrap = WhereBootstrap(),
    ) -> LifecycleSteps {
        LifecycleSteps {
            // Open the store, assemble the services, and create the session.
            // The build is skipped when services are already retained (a
            // preview/test injected them, or a prior session before a reset) so
            // we never spin up a real store + CoreLocation behind it; the
            // session is then (re)created from the retained layer. Opening may
            // run a lightweight migration; rather than predict it, key the
            // migration UI off slowness: if the open is still running after a
            // beat, show MigrationProgressView and hold it for a readable
            // minimum so a fast open never flashes it.
            LifecycleStep.work(LaunchStepID.openStore) { _ in
                guard model.session == nil else { return }
                if !model.hasServices {
                    try await model.attach(services: bootstrap.makeServices())
                }
                model.startSession()
            }
            .presenting(after: .milliseconds(500), minVisible: .seconds(1)) {
                MigrationProgressView(bridge: $0)
            }

            // First run only. `LifecycleStep.interactive` is `.modes(.foreground)`,
            // so a headless background launch skips it (and never deadlocks
            // waiting for a tap that can't come).
            LifecycleStep
                .interactive(LaunchStepID.onboarding) { OnboardingView(bridge: $0) }
                .when { !model.hasOnboarded }

            LifecycleStep.work(LaunchStepID.syncAuth) { _ in
                await model.session?.syncAuthorization()
                model.session?.observeAuthorizationChanges()
            }
            LifecycleStep.work(LaunchStepID.reconcileTracking) { _ in
                await model.session?.reconcileTracking()
            }
            LifecycleStep
                .work(LaunchStepID.loadYear) { _ in await model.session?.refresh() }
            LifecycleStep.work(LaunchStepID.reminders) { _ in
                await model.session?.applyReminderConfiguration()
            }
            LifecycleStep.work(LaunchStepID.summary) { _ in
                await model.session?.applySummaryConfiguration()
            }
            LifecycleStep.work(LaunchStepID.widgetSnapshot) { _ in
                await model.session?.refreshWidgetSnapshot()
            }
        }
    }

    /// The reverse of `sequence`: the teardown run by Settings' "Erase all data
    /// & reset". `LifecycleRunner.reset` runs these steps, then re-drives
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
    private var locationSource: CoreLocationSource?

    public init() {}

    /// Install the `CLLocationManager` + delegate right away, without touching
    /// the store. Idempotent.
    public func prepareLocation() {
        guard locationSource == nil else { return }
        locationSource = CoreLocationSource()
    }

    /// Open the SwiftData store (on a detached task so a slow lightweight
    /// migration runs off the main actor the migration UI renders on) and
    /// assemble the services from it and the prepared location source.
    /// Throws on persistence failure so the `open-store` step can surface it.
    public func makeServices() async throws -> WhereServices {
        let source = locationSource ?? CoreLocationSource()
        locationSource = nil
        let store = try await Task.detached(priority: .userInitiated) {
            try SwiftDataStore.make()
        }.value
        return WhereServices(store: store, locationSource: source)
    }
}
