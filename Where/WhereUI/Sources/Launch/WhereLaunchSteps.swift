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
//
// Each step also declares a span `budget` (see `BudgetedLaunchStep`), and
// `WhereLaunch.plan(for:)` composes them `.measured()` so every run is one
// Periscope span.

/// Open the SwiftData store and assemble the service layer — the process's
/// **one** store open (everything else shares the instance by injection; see
/// `WhereBootstrap.makeServices`). Skipped work when services already exist
/// (a preview/test injected them, or a prior session before a reset), so we
/// never spin up a real store + CoreLocation behind a retained layer.
/// Opening may run a lightweight migration; there's no separate UI for it —
/// the launch splash (shown throughout) fades in its own launch-neutral
/// "taking a moment" caption when any launch phase runs long.
struct OpenStoreStep: BudgetedLaunchStep {
    let model: WhereModel
    let bootstrap: WhereBootstrap

    let id = LaunchStepID.openStore
    /// The launch's heaviest step by design — a cold store open (possibly
    /// creating the file or running a lightweight migration) plus CoreLocation
    /// assembly. Past a second the splash caption is about to appear.
    let budget: Duration = .seconds(1)

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
struct StartSessionStep: BudgetedLaunchStep {
    let model: WhereModel
    let onServicesReady: @MainActor (WhereServices) async -> Void

    let id = LaunchStepID.startSession
    /// In-memory session construction plus the app's composition hook, which
    /// derives the App Intents stack from the already-open store rather than
    /// opening anything itself — so this should be fast.
    let budget: Duration = .milliseconds(250)

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

/// Stop GPS, wipe the store, and drop the session. Takes the session being
/// erased as the teardown plan's root input — handed in by Settings, not
/// re-read from an optional. If the erase throws the runner parks in
/// `.failed` (terminally — teardown runs fire-once) with the session and
/// preferences *intact*, so the reset is simply re-invocable from Settings
/// after relaunching, rather than stranding the user in onboarding atop
/// un-erased data.
struct EraseDataStep: BudgetedLaunchStep {
    let model: WhereModel

    let id = LaunchStepID.eraseData
    /// Quiescing GPS and wiping every table — the user is watching a
    /// progress-free Settings row, so this is the reset's one slow step.
    let budget: Duration = .seconds(3)

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
struct ResetPreferencesStep: BudgetedLaunchStep {
    let model: WhereModel

    let id = LaunchStepID.resetPreferences
    /// A handful of key-value writes.
    let budget: Duration = .milliseconds(100)

    func run(_: Void, _: LifecycleStepContext) async throws {
        model.resetPreferences()
    }
}
