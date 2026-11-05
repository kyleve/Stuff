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
// The trunk consumes a one-shot demo request, then resolves local identity before onboarding.
// The gate receives that context and passes it through unchanged. A world chosen at the gate
// reaches ResolveScopeStep through the model; subsequent steps receive the resolved scope.
//
// Each step also declares a span `budget` (see `BudgetedLaunchStep`), and
// the plans compose them `.measured()` so every run is one Periscope span.

/// Consume a one-shot demo request before the onboarding gate can resolve a
/// real scope. With no request this is a cheap pass-through launch node.
struct ActivateLaunchDemoStep: BudgetedLaunchStep {
    let model: WhereModel
    let id = LaunchStepID.activateDemo
    let budget: Duration = .seconds(3)

    func run(_: Void, _: LifecycleStepContext) async throws {
        try await model.activatePendingLaunchDemoIfNeeded()
    }
}

/// Resolve local identity before a gate can render or a scope can open. Unavailable identity
/// storage throws without creating an onboarding identity. An existing demo scope needs none.
struct ResolveInstallationContextStep: BudgetedLaunchStep {
    enum Context {
        case activeScope
        case installation(InstallationRecordingContext)
    }

    let model: WhereModel
    let id = LaunchStepID.resolveInstallation
    let budget: Duration = .seconds(1)

    func run(_: Void, _: LifecycleStepContext) async throws -> Context {
        if model.isInDemoMode { return .activeScope }
        let installation = try model.installationRecordingContext
        if model.activeScope != nil, installation.hasCompletedSetup { return .activeScope }
        return .installation(installation)
    }
}

/// Gates every launch reason on this installation's completed setup.
/// A restored onboarding preference cannot replace local consent. Confirmed
/// consent permits import recovery before presenting the remaining setup.
/// Unconfirmed installations wait for foreground input before opening services.
struct OnboardingGate: LifecycleGate {
    let model: WhereModel

    let id = LaunchStepID.onboarding
    let modes: LifecycleModeSet = .all

    func isNeeded(_ value: ResolveInstallationContextStep.Context) async -> Bool {
        guard case let .installation(context) = value else { return false }
        model.repairOnboardingFromCompletedImportIfNeeded()
        if model.hasInterruptedOnboardingImport, context.automaticRecordingEnabled != nil {
            switch await model.recoverInterruptedOnboardingImport(context: context) {
                case .needsOnboarding: return true
                case .recovered: return !context.hasCompletedSetup
                case .failed: return false
            }
        }
        // A failed setup may retain an open scope. Only durable completion
        // lets that scope bypass the gate.
        return !context.hasCompletedSetup || (model.activeScope == nil && !model.hasOnboarded)
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

    func run(
        _: ResolveInstallationContextStep.Context,
        _: LifecycleStepContext,
    ) async throws -> WhereScope {
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
    /// Reconcile pending share drafts before the service handoff. Attachment size can make
    /// this slower than ordinary in-memory session construction.
    let budget: Duration = .seconds(3)

    func run(_ scope: WhereScope, _: LifecycleStepContext) async throws -> WhereSession {
        let session = model.startSession(scope: scope)
        await model.importPendingSharedEvidenceIfNeeded()
        try session.services.validateDataAccess()
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
