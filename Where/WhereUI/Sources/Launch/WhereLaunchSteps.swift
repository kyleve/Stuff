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

/// First-run onboarding. Rooted at the trunk's head so that an install whose
/// user hasn't chosen yet builds nothing: no store is opened, no CloudKit is
/// contacted, and no session exists behind this.
///
/// Unlike most gates it applies to **all** launch reasons rather than the
/// foreground-only default. Parking a headless launch is the point here — the
/// alternative is opening the user's store for a launch they can't see and may
/// never have consented to — and it costs nothing: a genuine background wake
/// can only happen once location monitoring is running, which requires the
/// permission this flow asks for, by which point `isNeeded` is false.
struct OnboardingGate: LifecycleGate {
    let model: WhereModel

    let id = LaunchStepID.onboarding
    let modes: LifecycleModeSet = .all

    func isNeeded(_: Void) async -> Bool {
        // An active scope means the choice has already been made — by
        // onboarding just now, or by a preview/test injecting one — so don't
        // ask again even though `hasOnboarded` may not be written yet.
        model.activeScope == nil && !model.hasOnboarded
    }
}

/// Resolve the scope the rest of the launch runs against: the one the user's
/// choice at the gate activated, or — for someone who onboarded on an earlier
/// launch — their real scope, opening the app's **one** store on the way (see
/// `WhereModel.resolveScope()`; everything else shares that store by
/// injection). Opening may run a lightweight migration; there's no separate UI
/// for it — the launch splash (shown throughout) fades in its own
/// launch-neutral "taking a moment" caption when any launch phase runs long.
struct ResolveScopeStep: LifecycleStep {
    let model: WhereModel

    let id = LaunchStepID.resolveScope

    func run(_: Void, _: LifecycleStepContext) async throws -> WhereScope {
        try await model.resolveScope()
    }
}

/// Create the logged-in `WhereSession` over the active scope and hand the
/// scope's service layer to the app's composition hook before any later node —
/// or the UI — runs, so consumers awaiting it (parked App Intents) resume
/// against this session's store. Runs on every session (re)start: first
/// launch, a retry after a failed open, and the reset relaunch (the
/// teardown's fresh attempt clears the run-once memo).
struct StartSessionStep: LifecycleStep {
    let model: WhereModel
    let onServicesReady: @MainActor (WhereServices) async -> Void

    let id = LaunchStepID.startSession

    func run(_ scope: WhereScope, _: LifecycleStepContext) async throws -> WhereSession {
        let session = model.startSession(scope: scope)
        await onServicesReady(session.services)
        return session
    }
}

/// Read location authorization into the coordinator and start observing live
/// authorization + region-style changes. Stays on the trunk: the
/// reconcile-tracking step must see the synced authorization.
struct SyncAuthStep: LifecycleStep {
    let id = LaunchStepID.syncAuth

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
struct ReconcileTrackingStep: LifecycleStep {
    let id = LaunchStepID.reconcileTracking

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.reconcileTracking()
    }
}

/// Take a one-shot GPS fix for today if none is logged yet, so opening the
/// app on a fresh day fills the calendar in. Foreground-only — a headless
/// launch shouldn't spend a fresh fix (a `.background` relaunch is itself
/// the passive event); it runs once a scene promotes the launch.
struct CaptureTodayStep: LifecycleStep {
    let id = LaunchStepID.captureToday
    let modes: LifecycleModeSet = .foreground

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.captureTodayIfNeeded()
    }
}

/// Push the logging-reminder schedule + badge (backlog + issue count) to the
/// reconciler.
struct RemindersStep: LifecycleStep {
    let id = LaunchStepID.reminders

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.applyReminderConfiguration()
    }
}

/// Push the daily-summary recap to the reconciler.
struct SummaryStep: LifecycleStep {
    let id = LaunchStepID.summary

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.applySummaryConfiguration()
    }
}

/// Push the "issues to resolve" notification intent to its reconciler.
struct IssueAlertsStep: LifecycleStep {
    let id = LaunchStepID.issueAlerts

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.applyIssueAlertConfiguration()
    }
}

/// Republish the widget snapshot from whatever is already on disk, so a cold
/// launch with no writes this session doesn't leave the widget blank or
/// showing the previous day's "today".
struct WidgetSnapshotStep: LifecycleStep {
    let id = LaunchStepID.widgetSnapshot

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        await session.refreshWidgetSnapshot()
    }
}

// MARK: - Reset teardown steps

/// Stop GPS, wipe the store, and log out. Takes the session being erased as
/// the teardown plan's root input — handed in by Settings, not re-read from an
/// optional. If the erase throws the runner parks in `.failed` (terminally —
/// teardown runs fire-once) with the session and preferences *intact*, so the
/// reset is simply re-invocable from Settings after relaunching, rather than
/// stranding the user in onboarding atop un-erased data.
struct EraseDataStep: LifecycleStep {
    let model: WhereModel

    let id = LaunchStepID.eraseData

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        try await session.eraseSession()
        // Logging out drops the session and parks the relaunch on the
        // onboarding gate, but keeps the scope dormant — onboarding logs back
        // in to the same erased store rather than opening a second one.
        model.endSession()
    }
}

/// Clear the persisted preferences that gate the relaunch (onboarding flag,
/// tracking intent, reminder/summary schedules), so the next launch behaves
/// like a fresh install.
struct ResetPreferencesStep: LifecycleStep {
    let model: WhereModel

    let id = LaunchStepID.resetPreferences

    func run(_: Void, _: LifecycleStepContext) async throws {
        model.resetPreferences()
    }
}
