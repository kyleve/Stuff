import LifecycleKit
import WhereCore

// The typed steps `WhereLaunch.plan(for:)` and `resetPlan(for:)` assemble.
//
// Each step's `Input`/`Output` is the launch's dependency scope at that
// point (see the scope convention in `WhereLaunch`): `ResolveScopeStep` mints
// the logged-in scope (`WhereScope`), `StartSessionStep` promotes it to the
// session scope (`WhereSession`, which embeds the scope's services), and
// everything downstream takes the **non-optional** session as input — a step
// cannot be scheduled before the thing it needs exists.
//
// The trunk begins with the onboarding gate rather than a step, because
// nothing may be built until the user has chosen a world to work in. That is
// also the one place the "no step reaches into `WhereModel` for what an
// earlier node should have set" rule bends: a gate carries no value (it is
// pass-through by construction), so a choice made *at* the gate — onboarding
// logging in for real, or demo mode activating an in-memory scope — reaches
// `ResolveScopeStep` through the model rather than down the trunk. Every step
// after that is threaded normally.
//
// Each step also declares a span `budget` (see `BudgetedLaunchStep`), and
// the plans compose them `.measured()` so every run is one Periscope span.

/// First-run onboarding and this installation's recording choice.
/// Rooted at the trunk's head so that an install whose user hasn't chosen yet
/// builds nothing: no store is opened, no CloudKit is contacted, and no session
/// exists behind this.
///
/// Unlike most gates it applies to **all** launch reasons rather than the
/// foreground-only default. Parking a headless launch is the point here — the
/// alternative is opening the user's store for a launch they can't see and may
/// never have consented to. The non-backed-up recording context is also absent
/// after a restore onto another device even when the backed-up onboarding flag
/// is present; parking safely defers opening the store until the user verifies
/// that new installation's choice in foreground.
struct OnboardingGate: LifecycleGate {
    let model: WhereModel

    let id = LaunchStepID.onboarding
    let modes: LifecycleModeSet = .all

    func isNeeded(_: Void) async -> Bool {
        model.repairOnboardingFromCompletedImportIfNeeded()
        if model.hasInterruptedOnboardingImport {
            return await model.recoverInterruptedOnboardingImport()
        }
        // An active scope means the choice has already been made — by
        // onboarding just now, or by a preview/test injecting one — so don't
        // ask again even though `hasOnboarded` may not be written yet.
        return model.activeScope == nil
            && (!model.hasOnboarded || !model.hasConfirmedRecordingChoice)
    }
}

struct RejoinDeviceStep: BudgetedLaunchStep {
    let model: WhereModel
    let id = LaunchStepID.rejoinDevice
    let budget: Duration = .seconds(5)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        try await session.prepareDeviceRejoin()
        try await model.rejoinInstallation()
    }
}

/// Resolve the scope the rest of the launch runs against: the one the user's
/// choice at the gate activated, or — for someone who onboarded on an earlier
/// launch — their real scope, opening the app's **one** store on the way (see
/// `WhereModel.resolveScope()`; everything else shares that store by
/// injection). Before returning the scope, resolve any interrupted backup
/// import so neither App Intents nor recording can observe pre-cleanup state.
/// Opening may run a lightweight migration; there's no separate UI for it — the launch splash
/// (shown throughout) fades in its own
/// launch-neutral "taking a moment" caption when any launch phase runs long.
struct ResolveScopeStep: BudgetedLaunchStep {
    let model: WhereModel

    let id = LaunchStepID.resolveScope
    /// The launch's heaviest step by design — a cold store open (possibly
    /// creating the file or running a lightweight migration) plus CoreLocation
    /// assembly. Past a second the splash caption is about to appear.
    let budget: Duration = .seconds(1)

    func run(_: Void, _: LifecycleStepContext) async throws -> WhereScope {
        if let recoveryError = model.takeInterruptedOnboardingImportError() {
            throw recoveryError
        }
        let scope = try await model.resolveScope()
        try await model.preflightPendingImportRecovery(in: scope)
        return scope
    }
}

/// Create the logged-in `WhereSession` over the active scope and hand the
/// scope's service layer to the app's composition hook before any later node —
/// or the UI — runs, so consumers awaiting it (parked App Intents) resume
/// against this session's store. Runs on every session (re)start: first
/// launch, a retry after a failed open, and the reset relaunch (the
/// teardown's fresh attempt clears the run-once memo).
struct StartSessionStep: BudgetedLaunchStep {
    let model: WhereModel
    let onServicesReady: @MainActor (WhereServices) async -> Void

    let id = LaunchStepID.startSession
    /// In-memory session construction plus the app's composition hook, which
    /// derives the App Intents stack from the already-open store rather than
    /// opening anything itself — so this should be fast.
    let budget: Duration = .milliseconds(250)

    func run(_ scope: WhereScope, _: LifecycleStepContext) async throws -> WhereSession {
        let session = model.startSession(scope: scope)
        await onServicesReady(session.services)
        return session
    }
}

/// Read location authorization into the coordinator and start observing live
/// authorization + region-style changes. Stays on the trunk: the
/// reconcile-tracking step must see the synced authorization.
struct SyncAuthStep: BudgetedLaunchStep {
    let id = LaunchStepID.syncAuth
    /// A CoreLocation authorization read plus the primary-region fetch that
    /// seeds region styling — one small store read.
    let budget: Duration = .milliseconds(500)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.syncAuthorization()
        session.observeAuthorizationChanges()
        await session.seedRegionStyles()
        session.observeRegionStyleChanges()
    }
}

/// Start or stop GPS ingestion to match the user's intent + authorization.
/// Stays on the trunk, after `SyncAuthStep`, so it reconciles against the
/// authorization that step just synced.
struct ReconcileTrackingStep: BudgetedLaunchStep {
    let id = LaunchStepID.reconcileTracking
    /// Starting the ingestor loads and drains any outbox backlog, so this can
    /// legitimately outlast the other trunk steps after a spell offline.
    let budget: Duration = .seconds(1)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.reconcileTracking()
        await session.runAutomaticBackupIfDue()
    }
}

/// Take a one-shot GPS fix for today if none is logged yet, so opening the
/// app on a fresh day fills the calendar in. Foreground-only — a headless
/// launch shouldn't spend a fresh fix (a `.background` relaunch is itself
/// the passive event); it runs once a scene promotes the launch.
struct CaptureTodayStep: BudgetedLaunchStep {
    let id = LaunchStepID.captureToday
    let modes: LifecycleModeSet = .foreground
    /// Only *requests* the one-shot fix — the fix itself resolves on the
    /// ingestor, so this step returns without waiting for GPS.
    let budget: Duration = .milliseconds(250)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.captureTodayIfNeeded()
    }
}

/// Push the logging-reminder schedule + badge (backlog + issue count) to the
/// reconciler.
struct RemindersStep: BudgetedLaunchStep {
    let id = LaunchStepID.reminders
    /// Reconciling reminders reads the year report and scans for issues to
    /// compute the badge, then rewrites the notification schedule — detached,
    /// so a couple of seconds costs the user nothing.
    let budget: Duration = .seconds(2)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.applyReminderConfiguration()
    }
}

/// Push the daily-summary recap to the reconciler.
struct SummaryStep: BudgetedLaunchStep {
    let id = LaunchStepID.summary
    /// Also a year-report read, to build the recap body.
    let budget: Duration = .seconds(2)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.applySummaryConfiguration()
    }
}

/// Push the "issues to resolve" notification intent to its reconciler.
struct IssueAlertsStep: BudgetedLaunchStep {
    let id = LaunchStepID.issueAlerts
    /// The heaviest of the detached fan-out on a cold cache: a full issue scan
    /// runs every detector over the year's samples.
    let budget: Duration = .seconds(3)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.applyIssueAlertConfiguration()
    }
}

/// Republish the widget snapshot from whatever is already on disk, so a cold
/// launch with no writes this session doesn't leave the widget blank or
/// showing the previous day's "today".
struct WidgetSnapshotStep: BudgetedLaunchStep {
    let id = LaunchStepID.widgetSnapshot
    /// Republishing re-aggregates the year behind the snapshot when it's stale.
    let budget: Duration = .seconds(2)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.refreshWidgetSnapshot()
    }
}

// MARK: - Reset teardown steps

/// Remove old device identities, erase synced user data, discard pending fixes,
/// and log out. Takes the session being erased as
/// the teardown plan's root input — handed in by Settings, not re-read from an
/// optional. If the erase throws the runner parks in `.failed` (terminally —
/// teardown runs fire-once). An ordinary erase failure leaves the session and
/// preferences intact and remains
/// re-invocable from Settings. A `ResetCleanupError` means the destructive transaction did
/// commit, so this step logs out before surfacing the dedicated partial-success failure.
struct EraseDataStep: BudgetedLaunchStep {
    let model: WhereModel

    let id = LaunchStepID.eraseData
    /// Coordinating the recording barrier, data transaction, and sidecar cleanup —
    /// the user is watching a progress-free Settings row, so this is the reset's
    /// one slow step.
    let budget: Duration = .seconds(3)

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        do {
            try await session.eraseSession()
        } catch let error as WhereServices.ResetCleanupError {
            // The destructive store transaction committed. Release the scope even though local
            // cleanup remains, so App Intents cannot retain services over the erased store. The
            // installation context is intentionally left for a later reset retry.
            await model.endSession()
            throw error
        }
        // Logging out drops the session and releases the scope, so the relaunch parks on the
        // onboarding gate with nothing open; logging back in builds a fresh scope over the erased
        // store.
        await model.endSession()
    }
}

/// Leave the demo world behind. Takes the demo session as the teardown plan's
/// root input, the same shape the reset teardown uses, so Settings hands in
/// what it is tearing down rather than the step re-reading an optional.
///
/// There is deliberately no erase: a demo store only ever existed in memory,
/// so releasing the scope is the whole cleanup. Quitting the app mid-demo
/// takes the same path for free, which is why demo mode needs no teardown on
/// the cold-launch side.
struct ExitDemoStep: BudgetedLaunchStep {
    let model: WhereModel

    let id = LaunchStepID.exitDemo
    /// Drops in-memory state and detaches the demo scope's log routing — no
    /// disk work at all.
    let budget: Duration = .milliseconds(250)

    func run(_: WhereSession, _: LifecycleStepContext) async throws {
        await model.deactivateDemo()
    }
}

/// Clear the non-backed-up installation context and persisted preferences that
/// gate the relaunch, so the next launch behaves like a fresh install.
struct ResetPreferencesStep: BudgetedLaunchStep {
    let model: WhereModel

    let id = LaunchStepID.resetPreferences
    /// One sidecar removal plus a handful of key-value writes.
    let budget: Duration = .milliseconds(100)

    func run(_: Void, _: LifecycleStepContext) async throws {
        do {
            try model.resetPreferences()
        } catch let error as WhereServices.ResetCleanupError {
            throw error
        } catch {
            // EraseDataStep already committed synced erasure and released the old scope. A local
            // installation-context failure is therefore partial success, not a generic rollback.
            throw WhereServices.ResetCleanupError(underlying: error)
        }
    }
}
