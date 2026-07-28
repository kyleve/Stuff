import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// The long-lived, app-level model: the onboarding gate, the persisted
/// preferences, which `WhereScope` the app is logged in to, and the optional
/// `WhereSession` that holds everything scope-dependent (the loaded report,
/// GPS state, backup, …).
///
/// `WhereModel` exists for the whole process lifetime and is built before any
/// store opens (so a background relaunch can wire CoreLocation first). The
/// scope-backed state lives in `session`, which only exists once the launch has
/// resolved a scope — keeping the logged-out window (the intro, the splash)
/// free of any "is the store open yet?" nil-guarding spread across a
/// god-object.
///
/// **Nothing is opened until the user asks for it.** The launch parks on the
/// onboarding gate before any scope exists, so an install the user never
/// finishes onboarding creates no store file and contacts no CloudKit; the
/// real scope is built the moment they choose to use the app for real (see
/// ``resolveScope()``).
@MainActor
@Observable
public final class WhereModel {
    /// Which `WhereScope` the app is logged in to.
    ///
    /// An enum rather than an optional scope beside a set of flags: what the
    /// app is logged in to is one fact, and the states it can legally be in
    /// are few enough to enumerate.
    enum ScopeState {
        /// No scope active. Carries the real scope once one has been built and
        /// then logged out of (the reset teardown), so logging back in reuses
        /// that store instead of opening a second container over the same
        /// file — the race that once broke a fresh install's launch.
        case loggedOut(dormantReal: WhereScope?)
        /// Logged in to the user's real, persisted world.
        case real(WhereScope)
        /// Logged in to a throwaway demo world. The real scope rides along
        /// (dormant, and `nil` when the user never opened one — demoing from a
        /// fresh install), so it can't be lost while the demo runs and exiting
        /// doesn't have to reopen anything.
        case demo(active: WhereScope, dormantReal: WhereScope?)
    }

    /// The scope state, and with it the store the app is working against.
    private(set) var scopeState: ScopeState = .loggedOut(dormantReal: nil)

    /// The scope the app is logged in to, if any. Nil while logged out — the
    /// launch's `ResolveScopeStep` reads it to skip rebuilding a scope the
    /// user (or a preview) already put in place.
    public var activeScope: WhereScope? {
        switch scopeState {
            case .loggedOut: nil
            case let .real(scope): scope
            case let .demo(scope, _): scope
        }
    }

    /// Whether the app is running on demo data. Injected into the view tree as
    /// `\.isInDemoMode` (see `RootView`), which is how surfaces that must
    /// behave differently — Settings' exit button, the rows that would write
    /// something durable — find out without reaching for the model.
    public var isInDemoMode: Bool {
        if case .demo = scopeState { return true }
        return false
    }

    /// The logged-in, services-backed state, mirrored here for surfaces the
    /// launch container doesn't feed (the DEBUG developer overlay, the
    /// environment injection in `RootView`). The authoritative handoff is the
    /// launch itself: `StartSessionStep` returns the session and the runner's
    /// `.ready` carries it to the UI. Nil until that step runs; dropped by
    /// `endSession()` on reset and rebuilt when the launch re-drives.
    public private(set) var session: WhereSession?

    /// The durable log store the active scope records into, once it has
    /// opened — the DEBUG developer surface browses it. `nil` while logged out
    /// (those records reach OSLog only), and in previews/tests, which log
    /// through the in-memory pipeline.
    ///
    /// A scope's rather than the model's, because what is persisted depends on
    /// which world is active: the real scope writes to disk, an in-memory one
    /// keeps its records in memory.
    public var logStore: PeriscopeStore? {
        activeScope?.logStore
    }

    /// The persisted user intent (onboarding, tracking, reminder/summary
    /// schedules). Owns the defaults keys and the `reset()` the erase flow runs;
    /// shared by reference with the real scope, so onboarding's writes and the
    /// session's reads see the same store.
    ///
    /// App-scope rather than scope-owned: the onboarding gate reads
    /// `hasOnboarded` *before* any scope exists, to decide whether to park.
    /// Building it opens nothing — `UserDefaults` is already there — so
    /// holding it eagerly doesn't cost the logged-out window anything.
    let preferences: WherePreferences

    /// Assembles the pieces a real scope is built from. Held here rather than
    /// by the launch, because real-scope creation is now demand-driven:
    /// onboarding triggers it when the user commits to using the app for real,
    /// and the launch triggers it for an already-onboarded user.
    private let bootstrap: any WhereScopeAssembling

    private let now: @Sendable () -> Date

    /// The year the scene's `YearReportModel` opens on. Always the current year in
    /// the app; a preview/test can pin it via the services init.
    let initialSelectedYear: Int

    /// Preview/test seam: a report `MainTabs` seeds its `YearReportModel` with, so a
    /// `#Preview` renders populated content without a live store. Nil in the app
    /// (the scene loads from the store once it appears).
    let initialReport: YearReport?

    private static let logger = WhereLog.root(WhereModelLog.self)

    /// Whether first-run onboarding has been completed. Persisted so onboarding
    /// shows exactly once; the launch flow gates its onboarding step on this,
    /// and the reset/erase flow clears it so onboarding returns.
    public private(set) var hasOnboarded: Bool {
        get { preferences.hasOnboarded }
        set { preferences.hasOnboarded = newValue }
    }

    /// Mark first-run onboarding complete. Called by `OnboardingView` once the
    /// user finishes the intro (after the permission prompt resolves).
    public func completeOnboarding() {
        hasOnboarded = true
        Self.logger { .onboardingCompleted }
    }

    public static var currentYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.component(.year, from: Date())
    }

    /// The app-level model, logged out: no store is open, and none will be
    /// until something asks for a scope.
    ///
    /// - Parameter bootstrap: assembles the pieces a real scope is built from.
    ///   Substituted by tests that drive the logged-out → logged-in path,
    ///   which must not open the app's on-disk store or log store.
    public init(
        preferences: WherePreferences = WherePreferences(),
        bootstrap: any WhereScopeAssembling = WhereBootstrap(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.preferences = preferences
        self.bootstrap = bootstrap
        self.now = now
        initialSelectedYear = WhereModel.currentYear
        initialReport = nil
    }

    /// Preview/test seam: inject already-built services (and optionally a
    /// preloaded report) so SwiftUI previews and unit tests skip the live
    /// SwiftData + CoreLocation wiring. Activates a scope over them and builds
    /// the session up front, so the launch's `resolve-scope` step is a no-op and
    /// the model's `session` is ready to drive immediately.
    public init(
        services: WhereServices,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
        preferences: WherePreferences = WherePreferences(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        let scope = WhereScope(services: services, preferences: preferences)
        scopeState = .real(scope)
        self.preferences = preferences
        bootstrap = WhereBootstrap()
        self.now = now
        initialSelectedYear = selectedYear
        initialReport = report
        session = WhereSession(scope: scope, now: now)
    }

    /// Record a log store on the active scope for the developer surface to
    /// browse, without routing the shared pipeline into it. Previews and tests
    /// only — the app's scopes open their own.
    public func attach(logStore: PeriscopeStore) {
        activeScope?.attach(logStore: logStore)
    }

    /// Log in to `scope`. Idempotent: a no-op once a scope is active, so an
    /// injected preview/test scope is never clobbered, and the store an active
    /// scope holds is never displaced by a second one over the same file.
    public func activate(scope: WhereScope) {
        guard activeScope == nil else { return }
        scopeState = .real(scope)
    }

    /// The scope the app is logged in to, building the user's real one if
    /// nothing is active yet — the moment the app's on-disk store is opened.
    ///
    /// Two callers, both meaning "the user is using the app for real now": the
    /// launch's `resolve-scope` step (for someone who has already onboarded,
    /// so the gate before it didn't park), and onboarding itself (when they
    /// tap through the intro or restore a backup).
    ///
    /// The store is opened **at most once per process**. Logging out (the
    /// reset teardown) keeps the scope dormant rather than discarding it, so
    /// logging back in reuses that container: two `ModelContainer`s racing over
    /// one file is how a fresh install's launch once failed.
    ///
    /// Throws if the store can't be opened, leaving the model logged out so a
    /// later attempt can try again.
    func resolveScope() async throws -> WhereScope {
        switch scopeState {
            case let .real(scope), let .demo(scope, _):
                return scope
            case let .loggedOut(dormantReal):
                if let dormantReal {
                    scopeState = .real(dormantReal)
                    return dormantReal
                }
                let scope = try await WhereScope.real(
                    bootstrap: bootstrap,
                    preferences: preferences,
                )
                scopeState = .real(scope)
                Self.logger { .openedRealScope }
                return scope
        }
    }

    /// Install the location manager before anything async runs, so a
    /// background relaunch's queued significant-change or visit event is
    /// buffered rather than dropped. Runs on the launch's synchronous
    /// prerequisites path; opens no store, and prompts for nothing.
    public func prepareLocation() {
        bootstrap.prepareLocation()
    }

    // MARK: - Demo mode

    /// Log in to a demo world, keeping whatever real scope exists dormant
    /// beside it.
    ///
    /// Detaches the real scope's durable log sink first, so nothing logged
    /// during the demo is written to the user's on-disk history: a demo
    /// entered after a reset would otherwise still be journaling through the
    /// dormant real scope's store. The demo scope brings its own in-memory
    /// sink, so the logs are still there to browse — they just die with the
    /// process, like everything else in demo mode.
    public func activateDemo(_ scope: WhereScope) async {
        guard !isInDemoMode else { return }
        let dormantReal: WhereScope? = switch scopeState {
            case let .loggedOut(dormantReal): dormantReal
            case let .real(scope): scope
            case let .demo(_, dormantReal): dormantReal
        }
        await dormantReal?.detachLogSink()
        session = nil
        scopeState = .demo(active: scope, dormantReal: dormantReal)
        Self.logger { .enteredDemoMode }
    }

    /// Leave demo mode: drop the demo session and scope, and give the real
    /// scope its durable log sink back. The demo scope — its store, its
    /// preferences, its logs — is released here and never persisted anywhere.
    ///
    /// Lands logged out rather than back in the real world, because leaving a
    /// demo means the user hasn't chosen yet: the relaunch parks on the
    /// onboarding gate, which is where someone who has never onboarded belongs
    /// (and, for someone who has, resolves straight through to their data).
    public func deactivateDemo() async {
        guard case let .demo(active, dormantReal) = scopeState else { return }
        await active.detachLogSink()
        session = nil
        scopeState = .loggedOut(dormantReal: dormantReal)
        dormantReal?.reattachLogSink()
        Self.logger { .exitedDemoMode }
    }

    /// Create the logged-in `WhereSession` over `scope` and return it — the
    /// launch's `start-session` step consumes the return value directly (its
    /// typed output), rather than the session being re-read from an optional.
    /// Returns the existing session when one is already live (a preview/test
    /// built it up front). The re-driven launch after a reset rebuilds a fresh
    /// session here over the retained (now-erased) scope.
    func startSession(scope: WhereScope) -> WhereSession {
        if let session { return session }
        let session = WhereSession(scope: scope, now: now)
        self.session = session
        Self.logger { .startedSession(year: initialSelectedYear) }
        return session
    }

    /// Drop the logged-in session and log out, keeping the real scope dormant.
    /// Run by the reset teardown after `eraseAllData()`: the relaunch parks on
    /// the onboarding gate again (the teardown cleared `hasOnboarded`), and
    /// logging back in reuses this scope's already-open store rather than
    /// opening a second one.
    public func endSession() {
        session = nil
        if case let .real(scope) = scopeState {
            scopeState = .loggedOut(dormantReal: scope)
        }
        Self.logger { .endedSession }
    }

    // MARK: - Reset / erase all

    /// Clear every persisted preference so the next launch behaves like a fresh
    /// install: onboarding shows again (`hasOnboarded` gone), background
    /// tracking returns to its default intent, and the reminder/summary
    /// schedules revert to their defaults. The preferences half of the
    /// reset/erase teardown.
    ///
    /// `WherePreferences.reset()` removes the keys (rather than writing
    /// `false`/`0`) so the default-valued getters report first-install state
    /// again; the re-driven launch's fresh session reads those defaults back.
    public func resetPreferences() {
        preferences.reset()
        Self.logger { .resetPreferences }
    }
}
