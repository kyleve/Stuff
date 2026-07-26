import LifecycleKit
import WhereCore

// The typed steps `WhereLaunch.plan(for:)` and `resetPlan(for:)` assemble.
//
// Each step's `Input`/`Output` is the launch's dependency scope at that
// point (see the scope convention in `WhereLaunch`): `OpenStoreStep` mints
// the store scope (`WhereServices`), `StartSessionStep` promotes it to the
// session scope (`WhereSession`, which embeds the services), and everything
// downstream takes the **non-optional** session as input — a step cannot be
// scheduled before the thing it needs exists, and no step reaches into
// `WhereModel` optionals to find what an earlier step "should have" set.

/// Open the SwiftData store and assemble the service layer — the process's
/// **one** store open (everything else shares the instance by injection; see
/// `WhereBootstrap.makeServices`). Skipped work when services already exist
/// (a preview/test injected them, or a prior session before a reset), so we
/// never spin up a real store + CoreLocation behind a retained layer.
/// Opening may run a lightweight migration; there's no separate UI for it —
/// the launch splash (shown throughout) fades in its own launch-neutral
/// "taking a moment" caption when any launch phase runs long.
struct OpenStoreStep: LifecycleStep {
    let model: WhereModel
    let bootstrap: WhereBootstrap

    let id = LaunchStepID.openStore

    func run(_: Void, _: LifecycleStepContext) async throws -> WhereServices {
        if let services = model.services { return services }
        let services = try await bootstrap.makeServices()
        model.attach(services: services)
        return services
    }
}

/// Create the logged-in `WhereSession` over the assembled services and hand
/// the service layer to the app's composition hook before any later node —
/// or the UI — runs, so consumers awaiting it (parked App Intents) resume
/// against this session's store. Runs on every session (re)start: first
/// launch, a retry after a failed open, and the reset relaunch (the
/// teardown's fresh attempt clears the run-once memo).
struct StartSessionStep: LifecycleStep {
    let model: WhereModel
    let onServicesReady: @MainActor (WhereServices) async -> Void

    let id = LaunchStepID.startSession

    func run(_ services: WhereServices, _: LifecycleStepContext) async throws -> WhereSession {
        let session = model.startSession(services: services)
        await onServicesReady(session.services)
        return session
    }
}

/// First-run onboarding. A gate (foreground-only by default), so a headless
/// launch skips it — and `isNeeded` re-evaluates when a scene promotes the
/// launch, so a cold `.undetermined` start still onboards once it becomes
/// user-visible. `RootView` registers `OnboardingView` for this gate type;
/// the view receives the session this gate passes through.
struct OnboardingGate: LifecycleGate {
    let model: WhereModel

    let id = LaunchStepID.onboarding

    func isNeeded(_: WhereSession) async -> Bool {
        !model.hasOnboarded
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

/// Stop GPS, wipe the store, and drop the session. Takes the session being
/// erased as the teardown plan's root input — handed in by Settings, not
/// re-read from an optional. If the erase throws the runner parks in
/// `.failed` (terminally — teardown runs fire-once) with the session and
/// preferences *intact*, so the reset is simply re-invocable from Settings
/// after relaunching, rather than stranding the user in onboarding atop
/// un-erased data.
struct EraseDataStep: LifecycleStep {
    let model: WhereModel

    let id = LaunchStepID.eraseData

    func run(_ session: WhereSession, _: LifecycleStepContext) async throws {
        try await session.eraseSession()
        // Dropping the session makes the relaunch rebuild a fresh one over
        // the erased store (the services stay retained).
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
