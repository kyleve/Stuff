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
/// scope-backed state lives in `session`, which only exists once the launch's
/// `open-store` step has assembled a scope — keeping the brief pre-store
/// window (splash / migration UI) free of any "is the store open yet?"
/// nil-guarding spread across a god-object.
@MainActor
@Observable
public final class WhereModel {
    /// Which `WhereScope` the app is logged in to.
    ///
    /// An enum rather than an optional scope beside a set of flags: what the
    /// app is logged in to is one fact, and the states it can legally be in
    /// are few enough to enumerate.
    enum ScopeState {
        /// No scope yet — the pre-`open-store` window.
        case loggedOut
        /// Logged in to the user's real, persisted world.
        case real(WhereScope)
    }

    /// The scope state, and with it the store the app is working against.
    /// Retained across the app's lifetime once built: a reset rebuilds the
    /// session over the same (now erased) scope rather than reopening the
    /// store or rewiring CoreLocation.
    private(set) var scopeState: ScopeState = .loggedOut

    /// The scope the app is logged in to, if any. Nil only in the
    /// pre-`open-store` window; the launch's `OpenStoreStep` reads it to skip
    /// rebuilding a retained scope.
    var activeScope: WhereScope? {
        switch scopeState {
            case .loggedOut: nil
            case let .real(scope): scope
        }
    }

    /// The logged-in, services-backed state, mirrored here for surfaces the
    /// launch container doesn't feed (the DEBUG developer overlay, the
    /// environment injection in `RootView`). The authoritative handoff is the
    /// launch itself: `StartSessionStep` returns the session and the runner's
    /// `.ready` carries it to the UI. Nil until that step runs; dropped by
    /// `endSession()` on reset and rebuilt when the launch re-drives.
    public private(set) var session: WhereSession?

    /// The process-global Periscope log store, opened at launch and attached to
    /// `Periscope.shared` as its durable sink (see `WhereLaunch.bootstrapLogging`).
    /// Held here — not on `WhereSession` — because logging spans the whole
    /// process, not a login: it exists before the store opens and survives a
    /// reset. `nil` until the bootstrap opens it, and in previews/tests, which
    /// log only through the in-memory pipeline. The DEBUG developer surface reads
    /// it to browse persisted history.
    public private(set) var logStore: PeriscopeStore?

    /// The persisted user intent (onboarding, tracking, reminder/summary
    /// schedules). Owns the defaults keys and the `reset()` the erase flow runs;
    /// shared by reference with the `WhereSession` so both halves read/write the
    /// same store.
    let preferences: WherePreferences
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

    /// The app-level model: no services yet (the launch assembles them).
    public init(
        preferences: WherePreferences = WherePreferences(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.preferences = preferences
        self.now = now
        initialSelectedYear = WhereModel.currentYear
        initialReport = nil
    }

    /// Preview/test seam: inject already-built services (and optionally a
    /// preloaded report) so SwiftUI previews and unit tests skip the live
    /// SwiftData + CoreLocation wiring. Activates a scope over them and builds
    /// the session up front, so the launch's `open-store` step is a no-op and
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
        self.now = now
        initialSelectedYear = selectedYear
        initialReport = report
        session = WhereSession(scope: scope, now: now)
    }

    /// Retain the process-global log store the launch bootstrap opened and
    /// attached to `Periscope.shared`. Called once, off the launch critical
    /// path, so the developer surface can browse persisted history.
    public func attach(logStore: PeriscopeStore) {
        self.logStore = logStore
    }

    /// Log in to `scope` — the scope the launch's `open-store` step assembled
    /// (see `WhereBootstrap`). Idempotent: a no-op once a scope is active, so
    /// an injected preview/test scope is never clobbered, and the store an
    /// active scope holds is never displaced by a second one over the same
    /// file. `WhereBootstrap` owns *building* the services (store open +
    /// CoreLocation); the model just consumes the finished scope.
    public func activate(scope: WhereScope) {
        guard activeScope == nil else { return }
        scopeState = .real(scope)
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

    /// Drop the logged-in session (the services stay retained). Run by the
    /// reset teardown after `eraseAllData()`, so the re-driven launch rebuilds a
    /// fresh session over the erased store.
    public func endSession() {
        session = nil
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
