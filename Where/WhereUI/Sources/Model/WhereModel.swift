import Foundation
import LogKit
import Observation
import WhereCore

/// The long-lived, app-level model: the onboarding gate, the persisted
/// preferences, and the optional `WhereSession` that holds everything
/// services-dependent (the loaded report, GPS state, backup, …).
///
/// `WhereModel` exists for the whole process lifetime and is built before the
/// store opens (so a background relaunch can wire CoreLocation first). The
/// services-backed state lives in `session`, which only exists once the launch's
/// `open-store` step has assembled the service layer — keeping the brief
/// pre-store window (splash / migration UI) free of any "is the store open yet?"
/// nil-guarding spread across a god-object.
@MainActor
@Observable
public final class WhereModel {
    /// The assembled service layer, retained across the app's lifetime once
    /// built. Survives a reset (so the re-driven launch rebuilds the session
    /// from it rather than reopening the store / rewiring CoreLocation) and is
    /// the preview/test injection seam. Nil only in the pre-`open-store` window.
    private var services: WhereServices?

    /// The logged-in, services-backed state. Nil until the launch's
    /// `open-store` step calls `startSession()`; dropped by `endSession()` on
    /// reset and rebuilt when the launch re-drives. Logged-in views read it via
    /// `@Environment(WhereSession.self)`.
    public private(set) var session: WhereSession?

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

    private static let logger = WhereLog.channel(.model)

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
        Self.logger.info("Onboarding completed")
    }

    public static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
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
    /// SwiftData + CoreLocation wiring. Retains the services and builds the
    /// session up front, so the launch's `open-store` step is a no-op and the
    /// model's `session` is ready to drive immediately.
    public init(
        services: WhereServices,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
        preferences: WherePreferences = WherePreferences(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.services = services
        self.preferences = preferences
        self.now = now
        initialSelectedYear = selectedYear
        initialReport = report
        session = WhereSession(
            services: services,
            preferences: preferences,
            now: now,
        )
    }

    /// Whether the service layer has been assembled yet. The launch's
    /// `open-store` step reads this to skip building real services when a
    /// preview/test injected them up front.
    var hasServices: Bool {
        services != nil
    }

    /// Retain the service layer the launch's `open-store` step assembled (see
    /// `WhereBootstrap`). Idempotent — a no-op once services exist, so an
    /// injected preview/test value is never clobbered. `WhereBootstrap` owns
    /// *building* the services (store open + CoreLocation); the model just
    /// consumes the finished value.
    public func attach(services: WhereServices) {
        guard self.services == nil else { return }
        self.services = services
    }

    /// Create the logged-in `WhereSession` from the retained services. The
    /// launch's `open-store` step calls this after `attach(services:)`; a no-op
    /// when a session already exists or before services are attached. The
    /// re-driven launch after a reset rebuilds a fresh session here from the
    /// retained (now-erased) services.
    public func startSession() {
        guard session == nil, let services else { return }
        session = WhereSession(
            services: services,
            preferences: preferences,
            now: now,
        )
        Self.logger.info("Started session (year: \(initialSelectedYear))")
    }

    /// Drop the logged-in session (the services stay retained). Run by the
    /// reset teardown after `eraseAllData()`, so the re-driven launch rebuilds a
    /// fresh session over the erased store.
    public func endSession() {
        session = nil
        Self.logger.info("Ended session")
    }

    // MARK: - Reset / erase all

    /// Erase all persisted data, returning the app to a clean slate. Forwards to
    /// `WhereSession.eraseSession()` (which calls `WhereServices.reset()`); the
    /// data half of the reset/erase teardown (see `WhereLaunch.resetSequence`).
    /// Throws on persistence failure so the reset step parks the launcher in
    /// `.failed` rather than silently half-erasing.
    public func eraseAllData() async throws {
        try await session?.eraseSession()
    }

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
        Self.logger.info("Reset preferences to first-install defaults")
    }
}
