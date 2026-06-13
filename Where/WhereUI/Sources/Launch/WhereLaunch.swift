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
    /// `initializePrerequisites` (`prepareLocation`) installs the
    /// `CLLocationManager` synchronously so a background relaunch's queued event
    /// isn't lost while the async `open-store` step runs.
    public static func makeLauncher(model: WhereModel, reason: LifecycleReason) -> LifecycleRunner {
        LifecycleRunner(
            reason: reason,
            initializePrerequisites: { model.prepareLocation() },
            sequence: sequence(for: model),
        )
    }

    /// The ordered launch steps. The work steps run in the same order as
    /// `WhereModel.start()` (a parity test guards this); the only additions are
    /// the foreground-only `open-store` presentation and the `onboarding`
    /// gate, neither of which `start()` models.
    public static func sequence(for model: WhereModel) -> LifecycleSteps {
        LifecycleSteps {
            // Opening the store may run a schema migration; show the migration
            // UI only when one is predicted (the version marker is behind the
            // current schema), otherwise the splash stays up behind a fast open.
            LifecycleStep.work("open-store") { _ in try await model.openStore() }
                .presenting(when: { model.migrationExpected }) { MigrationProgressView(bridge: $0) }

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
