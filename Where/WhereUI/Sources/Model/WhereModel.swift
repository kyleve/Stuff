import Foundation
import Observation
import PeriscopeCore
@_spi(Testing) import WhereCore

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
    /// Observable bring-up state for the active scope's durable log store.
    ///
    /// The developer surface must not infer a failed asynchronous open from a
    /// missing optional: opening and failure are real states with different
    /// diagnostics. This mirror lives on the process model because SwiftUI
    /// observes it directly; the scope remains the store's lifetime owner.
    public enum LogStoreState {
        /// No scope is active, so durable logging has not been requested.
        case unavailable
        /// A real scope is active and its durable store is opening.
        case opening
        /// The active scope owns a usable store.
        case ready(PeriscopeStore)
        /// Opening failed. OSLog remains active, and the developer surface
        /// presents this exact diagnostic.
        case failed(description: String)
    }

    /// Which `WhereScope` the app is logged in to.
    ///
    /// An enum rather than an optional scope beside a set of flags: what the
    /// app is logged in to is one fact, and the states it can legally be in
    /// are few enough to enumerate.
    enum ScopeState {
        /// No scope active, carrying what it takes to build one. Logging in
        /// consumes the bootstrap, so a spent one — its location source handed
        /// over, its store opened — never lingers behind a live scope.
        case loggedOut(bootstrap: any WhereScopeAssembling)
        /// Logged in to the user's real, persisted world.
        case real(WhereScope)
        /// Logged in to a throwaway demo world.
        case demo(WhereScope)
    }

    /// The scope state, and with it the store the app is working against.
    private(set) var scopeState: ScopeState

    /// The scope the app is logged in to, if any. Nil while logged out — the
    /// launch's `ResolveScopeStep` reads it to skip rebuilding a scope the
    /// user (or a preview) already put in place.
    public var activeScope: WhereScope? {
        switch scopeState {
            case .loggedOut: nil
            case let .real(scope), let .demo(scope): scope
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

    /// Observable bring-up state for the active scope's durable log store.
    public private(set) var logStoreState = LogStoreState.unavailable

    /// The durable log store the active scope records into, once it has
    /// opened — the DEBUG developer surface browses it. `nil` while logged
    /// out, opening, or failed.
    ///
    /// A scope's rather than the model's, because what is persisted depends on
    /// which world is active: the real scope writes to disk, an in-memory one
    /// keeps its records in memory.
    public var logStore: PeriscopeStore? {
        if case let .ready(store) = logStoreState {
            return store
        }
        return nil
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

    /// Process reporting state stays real even while the active data scope is a demo.
    public let diagnosticReporting: DiagnosticReportingSettingsModel

    /// The active presentation theme. Onboarding can preview this value in
    /// memory before committing; Appearance Settings persists immediately.
    public private(set) var theme: WhereTheme

    /// The one device-local recording context store composed for this process.
    /// It owns the non-backed-up installation sidecar and is shared with every
    /// bootstrap this model creates, so onboarding and service assembly cannot
    /// resolve different identities.
    private let installationContextStore: any InstallationRecordingContextStoring
    private let onboardingImportRecovery: OnboardingImportRecoveryModel

    /// Makes the bootstrap a logged-out state carries. A factory rather than
    /// a stored instance, because a bootstrap is spent by the login it serves:
    /// logging out needs a fresh one for the next login, and holding the used
    /// one would keep a consumed location source alive beside the live scope.
    private let makeBootstrap:
        @MainActor (any InstallationRecordingContextStoring) -> any WhereScopeAssembling

    /// Called when the app logs out of a scope — a reset, or entering or
    /// leaving demo mode — so the composition root can release whatever it
    /// derived from that scope.
    ///
    /// The App Intents stack is the one that matters: it holds services over
    /// the store, and nothing else would release them before the *next* login
    /// opens a second container over the same file. Set once, at the app's
    /// composition root; the default no-op covers previews and tests.
    public var onLoggedOut: @MainActor () async -> Void = {}

    /// Keeps widgets and App Intents synchronized with Appearance Settings.
    public var onThemeChanged: @MainActor (WhereTheme) async -> Void = { _ in }

    @ObservationIgnored private var themeChangeTask: Task<Void, Never>?

    /// The logging system every scope this model creates records into. Carried
    /// rather than reached for: the app hands down `Periscope.shared` from its
    /// composition root, while tests and previews pass a private system so
    /// their sinks never join the process-wide pipeline.
    private let logSystem: Periscope

    private let now: @Sendable () -> Date

    /// The year the scene's `YearReportModel` opens on. Always the current year in
    /// the app; a preview/test can pin it via the services init.
    let initialSelectedYear: Int

    /// Preview/test seam: the complete value `MainTabs` seeds its
    /// `YearReportModel` with, so a `#Preview` renders populated content without
    /// a live store. Nil in the app (the scene loads once it appears).
    let initialYearDetails: YearReportDetails?

    private static let logger = WhereLog.root(WhereModelLog.self)

    /// Whether first-run onboarding has been completed. Persisted so onboarding
    /// shows exactly once; the launch flow gates its onboarding step on this,
    /// and the reset/erase flow clears it so onboarding returns.
    public private(set) var hasOnboarded: Bool {
        get { preferences.hasOnboarded }
        set { preferences.hasOnboarded = newValue }
    }

    /// The context onboarding renders. A newly proposed value is kept in memory
    /// until the user confirms it, so entering demo mode leaves no sidecar.
    public var installationRecordingContext: InstallationRecordingContext {
        installationContextStore.onboardingContext
    }

    /// Confirmation lives beside the non-backed-up installation identity, not
    /// in backed-up preferences. Restoring onto a new device therefore makes
    /// this false even when `hasOnboarded` arrived in the backup.
    public var hasConfirmedRecordingChoice: Bool {
        installationRecordingContext.automaticRecordingEnabled != nil
    }

    /// Derive an advisory local default from synced device status while the app remains logged out.
    func discoverRecordingRecommendation(
        for context: InstallationRecordingContext,
    ) async throws
        -> RecordingOnboardingRecommendation
    {
        if context.isRejoining {
            return RecordingOnboardingRecommendation(
                isEnabled: false,
                recentRecordingDevice: nil,
            )
        }
        guard case let .loggedOut(bootstrap) = scopeState else {
            let devices = try await activeScope?.services.recording.devices() ?? []
            return RecordingOnboardingRecommendation(
                for: context.currentDevice,
                devices: devices.map(\.device),
                now: now(),
            )
        }
        return try await RecordingOnboardingRecommendation(
            for: context.currentDevice,
            devices: bootstrap.discoverRecordingDevices(),
            now: now(),
        )
    }

    /// Whether the sidecar says onboarding crossed or may have crossed an import commit. The
    /// launch gate uses this one narrow exception to open the store before offering Restore.
    var hasInterruptedOnboardingImport: Bool {
        onboardingImportRecovery.hasInterruptedImport
    }

    /// Reassert the backed-up preference from the sidecar's terminal import authority. The
    /// sidecar write is the durable boundary because `UserDefaults` can return from its setter
    /// before the preference reaches disk.
    func repairOnboardingFromCompletedImportIfNeeded() {
        onboardingImportRecovery.repairCompletedImportIfNeeded(
            hasOnboarded: hasOnboarded,
            completeOnboarding: completeOnboarding,
        )
    }

    /// Resolve any onboarding import transaction left across a process death before launch
    /// exposes this scope to App Intents or starts recording.
    func preflightPendingImportRecovery(in scope: WhereScope) async throws {
        try await onboardingImportRecovery.preflightPendingImport(
            in: scope,
            completeOnboarding: completeOnboarding,
        )
    }

    /// Persist this installation's explicit onboarding choice, including a changed retry.
    @discardableResult
    public func confirmInitialRecordingChoice(
        isEnabled: Bool,
    ) throws -> InstallationRecordingContext {
        let context = try installationContextStore.resolve()
        if let existing = context.automaticRecordingEnabled {
            if existing != isEnabled {
                try installationContextStore.setAutomaticRecordingEnabled(isEnabled)
            }
            return try installationContextStore.resolve()
        }
        return try installationContextStore.confirmInitialRecording(isEnabled: isEnabled)
    }

    /// Mark the first-run app flow complete after its scope and selections have
    /// been committed. Recording confirmation is persisted separately first.
    public func completeOnboarding() {
        preferences.theme = theme
        publishThemeChange(theme)
        hasOnboarded = true
        Self.logger.onboardingCompleted()
    }

    /// Preview a theme without writing device preferences.
    public func previewTheme(_ newTheme: WhereTheme) {
        // RootView observes `theme` and passes it to `whereBroadwayRoot`, so
        // this assignment immediately re-resolves the live presentation tree.
        guard newTheme != theme else { return }
        theme = newTheme
    }

    /// Select and immediately persist a theme outside onboarding.
    public func selectTheme(_ newTheme: WhereTheme) {
        guard newTheme != theme || preferences.theme != newTheme else { return }
        theme = newTheme
        preferences.theme = newTheme
        publishThemeChange(newTheme)
    }

    /// Reassert the persisted device theme to app extensions at process launch.
    public func synchronizeTheme() {
        publishThemeChange(theme)
    }

    private func publishThemeChange(_ theme: WhereTheme) {
        themeChangeTask?.cancel()
        themeChangeTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await onThemeChanged(theme)
        }
    }

    /// Reconcile a cold-launch onboarding import before the Restore UI can be presented.
    /// Returns whether ordinary onboarding is still required.
    func recoverInterruptedOnboardingImport() async -> Bool {
        await onboardingImportRecovery.recoverInterruptedImport(
            requiresOnboarding: activeScope == nil
                && (!hasOnboarded || !hasConfirmedRecordingChoice),
            resolveScope: resolveScope,
            endSession: endSession,
            completeOnboarding: completeOnboarding,
        )
    }

    func takeInterruptedOnboardingImportError() -> (any Error)? {
        onboardingImportRecovery.takeInterruptedImportError()
    }

    public static var currentYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.component(.year, from: Date())
    }

    /// The app-level model, logged out: no store is open, and none will be
    /// until something asks for a scope.
    ///
    /// - Parameters:
    ///   - installationContextStore: one non-backed-up installation context,
    ///     shared with every bootstrap created for this model.
    ///   - makeBootstrap: makes the assembler a login builds from that same
    ///     context store. Called once per logged-out state, so a test can hand
    ///     back the same instance and count what was asked of it. Deliberately
    ///     has no default, for the same reason `logSystem` doesn't: a test that
    ///     omitted it would open the app's real durable stores on the next
    ///     login.
    ///   - logSystem: the logging system this model's scopes record into.
    ///     Deliberately has no default: the app passes `Periscope.shared`, and
    ///     a test that omitted it would silently attach its sinks to the
    ///     process-wide pipeline.
    public init(
        preferences: WherePreferences,
        installationContextStore: any InstallationRecordingContextStoring,
        makeBootstrap: @escaping @MainActor (
            any InstallationRecordingContextStoring,
        ) -> any WhereScopeAssembling,
        logSystem: Periscope,
        effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration? = nil,
        applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging = {
            _, _ in
        },
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.preferences = preferences
        diagnosticReporting = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: effectiveDiagnosticReportingConfiguration
                ?? preferences.diagnosticReportingConfiguration,
            applyRemoteLogging: applyRemoteLogging,
        )
        theme = preferences.theme
        self.installationContextStore = installationContextStore
        onboardingImportRecovery = OnboardingImportRecoveryModel(
            installationContextStore: installationContextStore,
        )
        self.makeBootstrap = makeBootstrap
        self.logSystem = logSystem
        self.now = now
        scopeState = .loggedOut(bootstrap: makeBootstrap(installationContextStore))
        initialSelectedYear = WhereModel.currentYear
        initialYearDetails = nil
    }

    /// Preview/test seam: inject already-built services (and optionally
    /// preloaded year details) so SwiftUI previews and unit tests skip the live
    /// SwiftData + CoreLocation wiring. Activates a scope over them and builds
    /// the session up front, so the launch's `resolve-scope` step is a no-op and
    /// the model's `session` is ready to drive immediately.
    ///
    /// Logging out and back in — a reset, or leaving demo mode — rebuilds over
    /// these same services rather than reaching for the real store, so a test
    /// can drive the whole cycle without touching disk.
    public init(
        services: WhereServices,
        details: YearReportDetails? = nil,
        selectedYear: Int = WhereModel.currentYear,
        preferences: WherePreferences,
        logSystem: Periscope,
        effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration? = nil,
        applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging = {
            _, _ in
        },
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        let installationContextStore = InMemoryInstallationRecordingContextStore(
            context: .testing,
        )
        let scope = WhereScope.fake(
            services: services,
            preferences: preferences,
            logSystem: logSystem,
        )
        scopeState = .real(scope)
        self.preferences = preferences
        diagnosticReporting = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: effectiveDiagnosticReportingConfiguration
                ?? preferences.diagnosticReportingConfiguration,
            applyRemoteLogging: applyRemoteLogging,
        )
        theme = preferences.theme
        self.installationContextStore = installationContextStore
        onboardingImportRecovery = OnboardingImportRecoveryModel(
            installationContextStore: installationContextStore,
        )
        makeBootstrap = { _ in InjectedServicesAssembler(services: services) }
        self.logSystem = logSystem
        self.now = now
        initialSelectedYear = selectedYear
        initialYearDetails = details
        session = WhereSession(
            scope: scope,
            installationContextStore: installationContextStore,
            now: now,
        )
    }

    /// Record a log store on the active scope for the developer surface to
    /// browse, without routing anything into it. Previews and tests only — the
    /// app's scopes open their own.
    ///
    /// A log store belongs to a scope, so there has to be one to give it to.
    /// Reaching here logged out is a miswired fixture rather than anything a
    /// user can do, so it trips in debug and is dropped in release.
    public func attach(logStore: PeriscopeStore) {
        guard let activeScope else {
            assertionFailure("No active scope to attach a log store to")
            return
        }
        activeScope.adopt(logStore: logStore)
        logStoreState = .ready(logStore)
    }

    /// Log in to `scope`. Idempotent: a no-op once a scope is active, so an
    /// injected preview/test scope is never clobbered, and the store an active
    /// scope holds is never displaced by a second one over the same file.
    public func activate(scope: WhereScope) {
        guard activeScope == nil else { return }
        scopeState = .real(scope)
        logStoreState = scope.logStoreState
    }

    /// The scope the app is logged in to, building the user's real one if
    /// nothing is active yet — the moment the app's on-disk store is opened.
    ///
    /// Two callers, both meaning "the user is using the app for real now": the
    /// launch's `resolve-scope` step (for someone who has already onboarded,
    /// so the gate before it didn't park), and onboarding itself (when they
    /// tap through the intro or restore a backup).
    ///
    /// **At most one scope is live at a time.** Logging out releases and tears
    /// the old one down, and the onboarding gate always sits between that and
    /// the next login, so the container this opens is the only one alive: two
    /// `ModelContainer`s racing over one file is how a fresh install's launch
    /// once failed, and it was their overlap that did it, not their number.
    ///
    /// Throws if the store can't be opened, leaving the model logged out so a
    /// later attempt can try again.
    public func resolveScope() async throws -> WhereScope {
        switch scopeState {
            case let .real(scope), let .demo(scope):
                return scope
            case let .loggedOut(bootstrap):
                let scope = try await WhereScope.real(
                    bootstrap: bootstrap,
                    preferences: preferences,
                    logSystem: logSystem,
                    onLogStoreStateChange: { [weak self] scope, state in
                        guard self?.activeScope === scope else { return }
                        self?.logStoreState = state
                    },
                )
                // Replacing the state releases the bootstrap: it has handed
                // over its location source and opened its store, and the next
                // login gets a fresh one.
                scopeState = .real(scope)
                logStoreState = scope.logStoreState
                Self.logger.openedRealScope()
                return scope
        }
    }

    /// Install the location manager before anything async runs, so a
    /// background relaunch's queued significant-change or visit event is
    /// buffered rather than dropped. Runs on the launch's synchronous
    /// prerequisites path; opens no store, and prompts for nothing.
    public func prepareLocation() {
        guard case let .loggedOut(bootstrap) = scopeState else { return }
        bootstrap.prepareLocation()
    }

    // MARK: - Demo mode

    /// Build a throwaway demo world — an in-memory store seeded with a
    /// plausible year — over this model's clock and logging system. Slow (it
    /// seeds a year), so the caller shows something while it runs.
    ///
    /// Separate from ``activateDemo(_:)`` because the entry point builds the
    /// scope *before* committing to it: a build that fails leaves the user on
    /// the intro with nothing changed.
    public func makeDemoScope() async throws -> WhereScope {
        try await WhereScope.demo(now: now, logSystem: logSystem)
    }

    /// Log in to a demo world, releasing whatever scope was active first.
    ///
    /// Logging out stops the real scope's durable log routing, so nothing
    /// logged during the demo reaches the user's on-disk history — the demo
    /// scope brings its own in-memory sink, so the records are still there to
    /// browse, they just die with the process like everything else here.
    ///
    /// One scope routes at a time because `Periscope` fans every record out to
    /// every registered sink: two worlds routing at once would cross-file each
    /// other's records, which is why a demo can't currently run *beside* the
    /// real app rather than instead of it.
    public func activateDemo(_ scope: WhereScope) async {
        guard !isInDemoMode else { return }
        await logOut()
        scopeState = .demo(scope)
        scope.startLogRouting()
        logStoreState = scope.logStoreState
        Self.logger.enteredDemoMode()
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
        guard isInDemoMode else { return }
        await logOut()
        Self.logger.exitedDemoMode()
    }

    /// Create the logged-in `WhereSession` over `scope` and return it — the
    /// launch's `start-session` step consumes the return value directly (its
    /// typed output), rather than the session being re-read from an optional.
    /// Returns the existing session when one is already live (a preview/test
    /// built it up front). The re-driven launch after a reset rebuilds a fresh
    /// session here over the retained (now-erased) scope.
    func startSession(scope: WhereScope) -> WhereSession {
        if let session { return session }
        let session = WhereSession(
            scope: scope,
            installationContextStore: scope.kind == .real ? installationContextStore : nil,
            now: now,
        )
        self.session = session
        Self.logger.startedSession(
            year: .restricted(.domainValue, initialSelectedYear),
        )
        return session
    }

    /// Drop the logged-in session and release the scope. Run by the reset
    /// teardown after `eraseAllData()` and when onboarding abandons a failed
    /// restore attempt: the next login builds a fresh scope over a newly-opened
    /// store and the installation context current at that attempt.
    public func endSession() async {
        await logOut()
        Self.logger.endedSession()
    }

    func rejoinInstallation() async throws {
        _ = try installationContextStore.rejoin()
        await logOut()
        Self.logger.endedSession()
    }

    /// Release whatever scope is active and return to logged out, ready to
    /// build a new one.
    ///
    /// Releasing rather than parking the scope is what keeps the store open
    /// once: the next login opens a fresh container, and the onboarding gate
    /// always sits between the two — every path here leaves `hasOnboarded`
    /// false or unset, so the relaunch parks for the user before anything
    /// re-opens. The old container is long gone by the time they answer.
    private func logOut() async {
        await activeScope?.stopLogRouting()
        session = nil
        scopeState = .loggedOut(bootstrap: makeBootstrap(installationContextStore))
        logStoreState = .unavailable
        await onLoggedOut()
    }

    // MARK: - Reset / erase all

    /// Clear the device-local installation context and every persisted
    /// preference so the next launch behaves like a fresh install: onboarding
    /// shows again, recording gets a new identity and explicit choice, and the
    /// reminder/summary schedules revert to their defaults.
    ///
    /// `WherePreferences.reset()` removes the keys (rather than writing
    /// `false`/`0`) so the default-valued getters report first-install state
    /// again; the re-driven launch's fresh session reads those defaults back.
    public func resetPreferences() throws {
        do {
            try installationContextStore.reset()
        } catch let error as WhereServices.ResetCleanupError {
            // The old installation identity is already retired. Finish the logical reset even
            // though deleting its tombstone still needs a retry, so a relaunch cannot combine a
            // fresh unconfirmed identity with stale "already onboarded" preferences.
            preferences.reset()
            diagnosticReporting.preferencesDidReset()
            theme = preferences.theme
            publishThemeChange(theme)
            Self.logger.resetPreferences()
            throw error
        }
        preferences.reset()
        diagnosticReporting.preferencesDidReset()
        theme = preferences.theme
        publishThemeChange(theme)
        Self.logger.resetPreferences()
    }
}

/// Hands back a service layer someone already assembled — the preview/test
/// counterpart to `WhereBootstrap`.
///
/// It exists so a model built with injected services can be logged out of and
/// back into without ever reaching for the real store: releasing a scope means
/// the next login *builds* one, and without this the default assembler would
/// quietly open the user's on-disk SwiftData and Periscope stores from inside
/// a test host.
private struct InjectedServicesAssembler: WhereScopeAssembling {
    let services: WhereServices

    func prepareLocation() {}

    func makeServices() async throws -> WhereServices {
        services
    }

    func discoverRecordingDevices() async throws -> [RecordingDevice] {
        []
    }

    /// No durable logging: a preview or test must leave nothing on disk and no
    /// sink on the logging system.
    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }
}
