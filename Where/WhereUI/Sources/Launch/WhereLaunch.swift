import LifecycleKit
import SwiftUI
import WhereCore

/// Assembles the Where app's cold-launch sequence and the `LifecycleRunner`
/// that drives it.
///
/// The sequence is only the *prerequisites*; the destination — the real tab UI
/// — is `LifecycleContainer`'s `content` (see `RootView`), shown once the
/// runner reaches `.ready`. It mirrors the imperative `WhereModel.start()`:
/// CoreLocation is wired synchronously in `initializePrerequisites`, then the
/// store opens and the rest of the work runs as ordered async steps.
@MainActor
public enum WhereLaunch {
    /// Build the runner for `model`, launching for `reason`.
    ///
    /// A `WhereBootstrap` owns the controller's assembly: its
    /// `prepareLocation()` runs as the runner's `initializePrerequisites`,
    /// installing the `CLLocationManager` synchronously so a background
    /// relaunch's queued event isn't lost while the async `open-store` step
    /// opens the store and assembles the controller.
    public static func makeLauncher(model: WhereModel, reason: LifecycleReason) -> LifecycleRunner {
        let bootstrap = WhereBootstrap()
        return LifecycleRunner(
            reason: reason,
            initializePrerequisites: { bootstrap.prepareLocation() },
            sequence: sequence(for: model, bootstrap: bootstrap),
        )
    }

    /// The ordered launch steps. The work steps run in the same order as
    /// `WhereModel.start()` (a parity test guards this); the only additions are
    /// the foreground-only `open-store` presentation and the `onboarding`
    /// gate, neither of which `start()` models.
    ///
    /// `bootstrap` assembles the controller in the `open-store` step; callers
    /// that only inspect the step list (the parity test) can rely on the
    /// default.
    public static func sequence(
        for model: WhereModel,
        bootstrap: WhereBootstrap = WhereBootstrap(),
    ) -> LifecycleSteps {
        LifecycleSteps {
            // Open the store and assemble the controller, then hand it to the
            // model. Skipped when a controller is already attached (a
            // preview/test injected one) so we never spin up a real store +
            // CoreLocation behind it. Opening may run a lightweight migration;
            // rather than predict it, key the migration UI off slowness: if the
            // open is still running after a beat, show MigrationProgressView and
            // hold it for a readable minimum so a fast open never flashes it.
            LifecycleStep.work("open-store") { _ in
                guard !model.hasController else { return }
                try await model.attach(controller: bootstrap.makeController())
            }
            .presenting(after: .milliseconds(500), minVisible: .seconds(1)) {
                MigrationProgressView(bridge: $0)
            }

            // First run only. `LifecycleStep.interactive` is `.modes(.foreground)`,
            // so a headless background launch skips it (and never deadlocks
            // waiting for a tap that can't come).
            LifecycleStep.interactive("onboarding") { OnboardingView(bridge: $0) }
                .when { !model.hasOnboarded }

            LifecycleStep.work("sync-auth") { _ in
                await model.syncAuthorization()
                model.observeAuthorizationChanges()
            }
            LifecycleStep.work("reconcile-tracking") { _ in await model.reconcileTracking() }
            LifecycleStep.work("load-year") { _ in await model.refresh() }
            LifecycleStep.work("reminders") { _ in await model.applyReminderConfiguration() }
            LifecycleStep.work("summary") { _ in await model.applySummaryConfiguration() }
            LifecycleStep.work("widget-snapshot") { _ in await model.refreshWidgetSnapshot() }
        }
    }

    /// The reverse of `sequence`: the teardown run by Settings' "Erase all data
    /// & reset". `LifecycleRunner.reset` runs these steps, then re-drives
    /// `sequence` from the top — which, with `hasOnboarded` now cleared, lands
    /// back on the onboarding step, returning the app to its first-run state.
    public static func resetSequence(for model: WhereModel) -> LifecycleSteps {
        LifecycleSteps {
            // Stop GPS and wipe the store first, then clear the preferences that
            // gate the relaunch (onboarding, tracking intent, reminders). If the
            // erase throws the runner parks in `.failed` and preferences are
            // left intact, so a retry re-erases rather than stranding the user
            // in onboarding atop un-erased data.
            LifecycleStep.work("erase-data") { _ in try await model.eraseAllData() }
            LifecycleStep.work("reset-preferences") { _ in model.resetPreferences() }
        }
    }
}

/// Owns the launch-time assembly of the `WhereController` so `WhereModel`
/// consumes a finished controller rather than wiring up persistence and
/// CoreLocation itself.
///
/// `prepareLocation()` runs synchronously as the runner's
/// `initializePrerequisites`, installing the `CLLocationManager` + delegate
/// early so a background relaunch's queued significant-change / visit event is
/// buffered (in `CoreLocationSource.sampleStream`) rather than dropped while
/// the async `open-store` step runs. `makeController()` then opens the store
/// off the main actor and assembles the controller from the two.
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
    /// assemble the controller from it and the prepared location source.
    /// Throws on persistence failure so the `open-store` step can surface it.
    public func makeController() async throws -> WhereController {
        let source = locationSource ?? CoreLocationSource()
        locationSource = nil
        let store = try await Task.detached(priority: .userInitiated) {
            try SwiftDataStore.make()
        }.value
        return WhereController(store: store, locationSource: source)
    }
}
