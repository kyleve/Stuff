import Foundation
import LogKit
import Observation
#if DEBUG
    import SwiftDataInspector
#endif
import WhereCore

/// The logged-in, services-backed state of the Where app: the selected year,
/// the loaded `YearReport`, GPS / permission state, the reminder + daily-summary
/// settings, and backup progress. Every mutation funnels through a
/// `WhereServices` collaborator so the views stay free of persistence and
/// CoreLocation details.
///
/// A session only exists once the store is open: `WhereModel` creates it in the
/// launch's `open-store` step and drops it on reset, so — unlike the old
/// `WhereModel` — `services` is non-optional and there are no pre-attach nil
/// guards. Logged-in views read it via `@Environment(WhereSession.self)`; the
/// `TabView` renders only at `.ready` and onboarding runs after `open-store`,
/// so the session is always present wherever those views appear.
@MainActor
@Observable
public final class WhereSession {
    /// Where the current year's data is in its load lifecycle. `failed`
    /// carries a user-presentable message.
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var selectedYear: Int
    public private(set) var report: YearReport?
    public private(set) var loadState: LoadState = .idle

    /// Unresolved data-quality issues for the selected year (Resolve tab + badge).
    public private(set) var dataIssues: [any DataIssue] = []

    public var dataIssueCount: Int {
        dataIssues.count
    }

    /// Whether background GPS ingestion is currently attached. Reflects reality
    /// (authorization + the user's intent), not just the last button tap.
    public private(set) var isTracking = false

    /// The latest known location authorization status, kept live via
    /// `LocationIngestor.authorizationUpdates()`.
    public private(set) var authorizationStatus: LocationAuthorizationStatus = .notDetermined

    /// Set when a location-permission request comes back denied/restricted,
    /// so the UI can offer to open Settings.
    public var permissionDenied = false

    /// Whether the daily "log before the day ends" reminder is enabled. Persists
    /// across launches; defaults to on so the safety net is active out of the
    /// box. Settable so SwiftUI can drive it through a plain key-path binding;
    /// the setter persists the intent and reconciles the schedule/badge.
    public var remindersEnabled: Bool {
        get { remindersEnabledStorage }
        set {
            guard newValue != remindersEnabledStorage else { return }
            remindersEnabledStorage = newValue
            preferences.remindersEnabled = newValue
            Task { await applyReminderConfiguration() }
        }
    }

    /// Time of day the daily reminder fires. Persists and reconciles on change.
    public var reminderTime: ReminderTime {
        get { reminderTimeStorage }
        set {
            guard newValue != reminderTimeStorage else { return }
            reminderTimeStorage = newValue
            preferences.reminderTime = newValue
            Task { await applyReminderConfiguration() }
        }
    }

    /// `Date`-typed projection of `reminderTime` for the Settings `DatePicker`,
    /// which works in `Date`. Lets the view bind `$session.reminderTimeOfDay`
    /// directly instead of building a closure binding; writes round-trip back
    /// into `reminderTime` (and its persistence/reconcile).
    public var reminderTimeOfDay: Date {
        get {
            calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: now(),
            ) ?? now()
        }
        set {
            let components = calendar.dateComponents([.hour, .minute], from: newValue)
            reminderTime = ReminderTime(
                hour: components.hour ?? ReminderTime.defaultEvening.hour,
                minute: components.minute ?? ReminderTime.defaultEvening.minute,
            )
        }
    }

    /// Whether the daily summary recap notification is enabled. Persists across
    /// launches; defaults to on so the year-to-date recap arrives out of the
    /// box. Settable so SwiftUI can drive it through a plain key-path binding;
    /// the setter persists the intent and reconciles the scheduled summary.
    public var summaryEnabled: Bool {
        get { summaryEnabledStorage }
        set {
            guard newValue != summaryEnabledStorage else { return }
            summaryEnabledStorage = newValue
            preferences.summaryEnabled = newValue
            Task { await applySummaryConfiguration() }
        }
    }

    /// Time of day the daily summary fires. Persists and reconciles on change.
    public var summaryTime: ReminderTime {
        get { summaryTimeStorage }
        set {
            guard newValue != summaryTimeStorage else { return }
            summaryTimeStorage = newValue
            preferences.summaryTime = newValue
            Task { await applySummaryConfiguration() }
        }
    }

    /// `Date`-typed projection of `summaryTime` for the Settings `DatePicker`,
    /// mirroring `reminderTimeOfDay`. Writes round-trip into `summaryTime` (and
    /// its persistence/reconcile).
    public var summaryTimeOfDay: Date {
        get {
            calendar.date(
                bySettingHour: summaryTime.hour,
                minute: summaryTime.minute,
                second: 0,
                of: now(),
            ) ?? now()
        }
        set {
            let components = calendar.dateComponents([.hour, .minute], from: newValue)
            summaryTime = ReminderTime(
                hour: components.hour ?? ReminderTime.defaultMorning.hour,
                minute: components.minute ?? ReminderTime.defaultMorning.minute,
            )
        }
    }

    /// Observed backing storage for `remindersEnabled` / `reminderTime`. The
    /// public computed properties layer persistence + reconciliation onto their
    /// setters, which a stored property can't express.
    private var remindersEnabledStorage: Bool
    private var reminderTimeStorage: ReminderTime

    /// Observed backing storage for `summaryEnabled` / `summaryTime`, mirroring
    /// the reminder storage above.
    private var summaryEnabledStorage: Bool
    private var summaryTimeStorage: ReminderTime

    /// GPS border-drift detection threshold (device setting).
    public var driftThreshold: DriftThreshold {
        get { DriftThreshold(rawValue: preferences.driftThresholdMeters) ?? .default }
        set {
            guard newValue.rawValue != preferences.driftThresholdMeters else { return }
            preferences.driftThresholdMeters = newValue.rawValue
            Task { await refreshDataIssues(force: true) }
        }
    }

    /// Whether the system has granted notification permission. Lets the Settings
    /// UI route the user to the system Settings app when they've enabled
    /// reminders but denied permission.
    public private(set) var notificationsAuthorized = false

    /// The services every mutation funnels through. Non-optional: a session only
    /// exists once `WhereModel` has assembled the service layer.
    let services: WhereServices
    /// `@ObservationIgnored` (it's plumbing, not observable UI state) and
    /// `nonisolated(unsafe)` so the `deinit` can cancel it. The unsafety is sound:
    /// every read/write is on the main actor except the `deinit`, which by
    /// definition runs with no other live references, so there is no concurrent
    /// access to race.
    @ObservationIgnored private nonisolated(unsafe) var authorizationTask: Task<Void, Never>?

    /// The persisted user intent (tracking, reminder/summary schedules) the
    /// session mirrors into its observable storage. Owned by `WhereModel` and
    /// shared by reference so onboarding (model) and the logged-in UI (session)
    /// read/write the same store.
    let preferences: WherePreferences
    private let now: @Sendable () -> Date

    /// Gregorian calendar in the current time zone — matches the day keys the
    /// aggregator produces in `report.days`, so the missing-day math lines up.
    let calendar: Calendar

    private static let logger = WhereLog.channel(.session)

    /// The authorization the degradation warning was last evaluated against.
    /// `syncAuthorization()` runs on every foreground, so warning only on a
    /// *change* keeps a steady degraded state (e.g. When-In-Use) from repeating
    /// the same line on each one.
    private var lastWarnedAuthorization: LocationAuthorizationStatus?

    /// Whether the "enabled but notifications not authorized" warning has been
    /// emitted for the current state, so it fires on entry into that state
    /// rather than on every configuration apply (which also runs per foreground).
    private var warnedRemindersUnauthorized = false
    private var warnedSummaryUnauthorized = false

    /// Persisted user intent to track in the background. Effective tracking is
    /// this AND `.always` authorization; we default to `true` so that, once the
    /// user grants Always, tracking resumes automatically on every launch.
    private var wantsTracking: Bool {
        get { preferences.wantsTracking }
        set { preferences.wantsTracking = newValue }
    }

    /// Primary/secondary split of the current report, or an empty ranking
    /// while nothing is loaded.
    public var ranking: RegionRanking {
        guard let report else { return RegionRanking(primary: [], secondary: []) }
        return RegionRanking(report: report)
    }

    /// Total distinct days with any tracked presence in the loaded year.
    public var trackedDayCount: Int {
        report?.days.count ?? 0
    }

    /// Unlogged days this year (Jan 1 through today), collapsed into ranges, for
    /// the warning banner and the backfill flow. Empty unless the user is
    /// viewing the current year, since past years can't gain "today" coverage by
    /// opening the app.
    public var missingDays: [MissingDayRange] {
        guard let report, isViewingCurrentYear else { return [] }
        let present = Set(report.days.map(\.date))
        // Through yesterday: today is still loggable, so it isn't a "missed" day
        // yet — the evening reminder covers it instead of the banner/backfill.
        return MissingDays.missingRanges(
            year: report.year,
            through: MissingDays.backlogCutoff(asOf: now(), calendar: calendar),
            present: present,
            calendar: calendar,
        )
    }

    /// Total number of unlogged days behind `missingDays`.
    public var missingDayCount: Int {
        missingDays.reduce(0) { $0 + $1.dayCount }
    }

    /// The session's notion of "now", forwarded for calendar and missing-day
    /// math in views and tests.
    public var referenceDate: Date {
        now()
    }

    /// Start-of-day keys for days that still need logging in the loaded year.
    public var missingDayKeys: Set<Date> {
        guard let report, isViewingCurrentYear else { return [] }
        return Set(MissingDays.missingDayKeys(
            year: report.year,
            through: MissingDays.backlogCutoff(asOf: now(), calendar: calendar),
            present: Set(report.days.map(\.date)),
            calendar: calendar,
        ))
    }

    private var isViewingCurrentYear: Bool {
        selectedYear == calendar.component(.year, from: now())
    }

    /// Number of calendar days in the selected year (365, or 366 in a leap
    /// year). Region cards scale their ambient progress bar against this rather
    /// than a hardcoded 365.
    public var daysInSelectedYear: Int {
        let calendar = Calendar.current
        guard
            let midYear = calendar.date(from: DateComponents(
                year: selectedYear,
                month: 6,
                day: 15,
            )),
            let range = calendar.range(of: .day, in: .year, for: midYear)
        else { return 365 }
        return range.count
    }

    /// Build a session over an already-assembled service layer. `report` is the
    /// preview/test seam: a non-nil value lands `loadState` at `.loaded` so
    /// `#Preview`s render content synchronously without driving `start()`.
    public init(
        services: WhereServices,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
        preferences: WherePreferences = WherePreferences(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.services = services
        self.report = report
        self.selectedYear = selectedYear
        self.preferences = preferences
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        remindersEnabledStorage = preferences.remindersEnabled
        reminderTimeStorage = preferences.reminderTime
        summaryEnabledStorage = preferences.summaryEnabled
        summaryTimeStorage = preferences.summaryTime
        loadState = report == nil ? .idle : .loaded
    }

    /// Cancel the authorization observer when the session is dropped (e.g. the
    /// reset teardown rebuilds a fresh session over the same retained services).
    /// Each session subscribes to its own `authorizationUpdates` stream (fanned
    /// out by `AuthorizationStatusBroadcaster`); cancelling here tears this
    /// session's subscription down promptly rather than letting the task linger
    /// until the next status change resumes it.
    deinit {
        authorizationTask?.cancel()
    }

    /// Sync authorization, resume tracking if appropriate, then load the
    /// selected year. Safe to call repeatedly; the authorization observer is
    /// only set up once.
    ///
    /// This is the imperative equivalent of `WhereLaunch.sequence`'s work steps,
    /// kept for previews/tests that drive the session directly without a
    /// `LifecycleRunner`.
    public func start() async {
        await syncAuthorization()
        observeAuthorizationChanges()
        await reconcileTracking()
        await refresh()
        await applyReminderConfiguration()
        await applySummaryConfiguration()
        await refreshDataIssues(force: false)
        // Republish the widget snapshot from whatever is already on disk so a
        // cold launch with no writes this session doesn't leave the widget
        // blank or showing the previous day's "today".
        await refreshWidgetSnapshot()
    }

    /// Refresh state that can change while the app is away, including
    /// notification permission edits made in Settings and calendar-day rollover.
    public func appBecameActive() async {
        await syncAuthorization()
        await reconcileTracking()
        await refresh()
        await applyReminderConfiguration()
        await applySummaryConfiguration()
        await refreshDataIssues(force: false)
        // The calendar day may have rolled over while backgrounded; recompute
        // so the widget's "today" reflects the current day rather than stale
        // foreground state.
        await refreshWidgetSnapshot()
    }

    /// Republish the widget snapshot from whatever is on disk. A launch step
    /// in its own right (see `WhereLaunch.sequence`).
    public func refreshWidgetSnapshot() async {
        await services.widgets.refreshIfStale()
    }

    /// Read the current authorization status from the ingestor into our
    /// observable state. Does not surface the permission alert — that's
    /// reserved for explicit user actions. A launch step (see
    /// `WhereLaunch.sequence`).
    func syncAuthorization() async {
        authorizationStatus = await services.ingestor.authorizationStatus()
        warnIfAuthorizationDegraded()
    }

    /// Emit a warning when the live authorization can't support background
    /// tracking, so the in-app log explains why GPS isn't running. Only fires on
    /// an actual status change — `syncAuthorization()` polls on every foreground,
    /// so an unconditional warn would repeat the same line each time. `always`
    /// and the transient `notDetermined` are expected states and stay quiet (but
    /// still update the dedup marker, so re-entering a degraded state warns).
    private func warnIfAuthorizationDegraded() {
        guard authorizationStatus != lastWarnedAuthorization else { return }
        lastWarnedAuthorization = authorizationStatus
        switch authorizationStatus {
            case .always, .notDetermined:
                break
            case .whenInUse:
                Self.logger.warning(
                    "Location authorized for When-In-Use only; background tracking unavailable",
                )
            case .denied, .restricted:
                Self.logger.warning(
                    "Location access \(authorizationStatus); background tracking unavailable",
                )
        }
    }

    /// Subscribe to live authorization changes (prompt results, Settings-app
    /// edits) so the indicator and tracking state stay in sync. Idempotent.
    func observeAuthorizationChanges() {
        guard authorizationTask == nil else { return }
        // Capture the value-type services locally so the long-lived stream loop
        // keeps `self` weak (an injected services reference, not the session).
        let services = services
        authorizationTask = Task { @MainActor [weak self] in
            let updates = await services.ingestor.authorizationUpdates()
            for await status in updates {
                guard let self else { break }
                authorizationStatus = status
                warnIfAuthorizationDegraded()
                await reconcileTracking()
            }
        }
    }

    /// Start or stop GPS ingestion so it matches the user's intent and the
    /// current authorization. Tracking only runs with Always authorization. A
    /// launch step (see `WhereLaunch.sequence`).
    func reconcileTracking() async {
        let wasTracking = isTracking
        if wantsTracking, authorizationStatus.allowsBackgroundTracking {
            await services.ingestor.start()
            isTracking = true
            if !wasTracking { Self.logger.info("Background tracking started") }
        } else {
            await services.ingestor.stop()
            isTracking = false
            if wasTracking { Self.logger.info("Background tracking stopped") }
        }
    }

    public func select(year: Int) async {
        guard year != selectedYear else { return }
        Self.logger.info("Selected year \(year)")
        selectedYear = year
        // Drop the previous year's report so views fall back to their loading
        // state instead of rendering stale data under the new year's label.
        report = nil
        await refresh()
        await refreshDataIssues(force: true)
    }

    func refreshDataIssues(force: Bool) async {
        do {
            dataIssues = try await services.resolution.issues(
                year: selectedYear,
                primaryRegions: ranking.primary.map(\.region),
                driftThresholdMeters: Double(preferences.driftThresholdMeters),
                force: force,
            )
        } catch {
            // Surface the failure in the log and keep the last good list rather
            // than silently blanking the tab + badge (which would read as "all
            // clear"). The report's own `loadState` already covers the common
            // case where the shared store is unreadable.
            Self.logger.warning(
                "Failed to scan for data issues: \(error.localizedDescription)",
            )
        }
    }

    public func dismiss(_ issue: any DataIssue) async {
        guard issue.isDismissible else { return }
        do {
            try await services.journal.dismissIssue(key: issue.id.storageKey)
            dataIssues.removeAll { $0.id == issue.id }
            await refreshDataIssues(force: true)
        } catch {
            Self.logger.warning(
                "Failed to dismiss data issue \(issue.id.storageKey): \(error.localizedDescription)",
            )
        }
    }

    public func refresh() async {
        // Capture the year this fetch is for. `WhereSession` is reentrant while
        // awaiting `yearReport`, so a rapid second `select(year:)` can start a
        // newer fetch that finishes first; without this guard a slower older
        // fetch could install its report under the newer year's label.
        let requestedYear = selectedYear
        loadState = .loading
        do {
            let report = try await services.reports.yearReport(for: requestedYear)
            guard requestedYear == selectedYear else { return }
            self.report = report
            loadState = .loaded
            Self.logger
                .info("Year report loaded for \(requestedYear) (\(report.days.count) day(s))")
        } catch {
            guard requestedYear == selectedYear else { return }
            loadState = .failed(error.localizedDescription)
            Self.logger.warning(
                "Failed to load year report for \(requestedYear): \(error.localizedDescription)",
            )
        }
    }

    /// Persist a single manual day. Throws on persistence failure so the
    /// caller (the entry form) can keep itself open and show the error inline
    /// instead of dismissing as if the save succeeded.
    public func setManualDay(date: Date, regions: Set<Region>) async throws {
        try await services.journal.addManualDay(date: date, regions: regions)
        await refresh()
        await refreshDataIssues(force: true)
    }

    /// Persist a manual day range. Throws on persistence failure (see
    /// `setManualDay(date:regions:)`).
    public func setManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
    ) async throws {
        try await services.journal.addManualDays(from: start, through: end, regions: regions)
        await refresh()
        await refreshDataIssues(force: true)
    }

    /// Authoritatively set a day's regions, *replacing* whatever was
    /// attributed to it (the Elsewhere "fix this day" path) rather than
    /// unioning. Throws on persistence failure so the editor can stay open and
    /// surface the error instead of dismissing as if the save succeeded.
    public func overrideDay(date: Date, regions: Set<Region>) async throws {
        try await services.journal.overrideDay(date: date, regions: regions)
        await refresh()
        await refreshDataIssues(force: true)
    }

    /// Undo a day's manual override/backfill, restoring the GPS-detected
    /// regions (the relabel "reset to GPS" action). Throws on persistence
    /// failure so the editor can stay open and surface the error.
    public func clearManualDay(date: Date) async throws {
        try await services.journal.clearManualDay(date: date)
        await refresh()
        await refreshDataIssues(force: true)
    }

    /// The days in the loaded report whose presence includes `region`, sorted
    /// ascending (matching `report.days`). Powers the Elsewhere drill-in list
    /// so the user can see where a region's check-ins landed and correct them.
    public func days(in region: Region) -> [DayPresence] {
        guard let report else { return [] }
        return report.days.filter { $0.regions.contains(region) }
    }

    /// The raw coordinates recorded inside `region` during the selected year,
    /// grouped by day, for the Elsewhere drill-in's map and place names.
    /// Returns an empty array (rather than throwing) on failure, so the view
    /// can simply render nothing.
    public func locations(in region: Region) async -> [RegionDayLocations] {
        await (try? services.reports.locations(in: region, year: selectedYear)) ?? []
    }

    /// One representative coordinate per region for the selected year (the
    /// most heavily sampled spot in each), for the Elsewhere cards' place-name
    /// teaser. Empty on failure.
    public func representativeCoordinates() async -> [Region: Coordinate] {
        await (try? services.reports.representativeCoordinates(for: selectedYear)) ?? [:]
    }

    /// Explicitly (re)request location access, e.g. from the "Grant location
    /// access" button. Drives the system prompt when possible, then syncs the
    /// status and reconciles tracking so the UI reflects the outcome.
    public func requestPermission() async {
        do {
            try await services.ingestor.requestPermission()
            permissionDenied = false
        } catch {
            // `.denied` / `.restricted` mean re-prompting won't help, so the UI
            // routes the user to the Settings app.
            permissionDenied = true
        }
        await syncAuthorization()
        await reconcileTracking()
        if authorizationStatus.allowsBackgroundTracking {
            Self.logger.info("Location permission granted (\(authorizationStatus))")
        }
    }

    /// Turn on background tracking. Records the intent, requests permission if
    /// needed, then reconciles — `isTracking` only flips on once Always
    /// authorization is in hand and GPS is actually running. When only
    /// When-In-Use is granted the indicator guides the user to Settings; on a
    /// hard denial the Settings alert is surfaced.
    public func startTracking() async {
        wantsTracking = true
        do {
            try await services.ingestor.requestPermission()
            permissionDenied = false
        } catch {
            permissionDenied = true
        }
        await syncAuthorization()
        await reconcileTracking()
        if authorizationStatus.allowsBackgroundTracking {
            Self.logger.info("Tracking enabled with background authorization")
        }
    }

    public func stopTracking() async {
        wantsTracking = false
        await services.ingestor.stop()
        isTracking = false
        Self.logger.info("Stopped background tracking")
    }

    /// Push the current reminder intent to the reminder reconciler and refresh
    /// whether the system has granted notification permission. A launch step
    /// (see `WhereLaunch.sequence`).
    func applyReminderConfiguration() async {
        await services.reminders.configure(enabled: remindersEnabled, time: reminderTime)
        notificationsAuthorized = await services.reminders.isAuthorized()
        if remindersEnabled, !notificationsAuthorized {
            if !warnedRemindersUnauthorized {
                Self.logger.warning("Logging reminders enabled but notifications not authorized")
                warnedRemindersUnauthorized = true
            }
        } else {
            warnedRemindersUnauthorized = false
        }
    }

    /// Push the current daily-summary intent to the summary reconciler and
    /// refresh whether the system has granted notification permission.
    /// Notification permission is global, so it shares `notificationsAuthorized`
    /// with the logging reminder. A launch step (see `WhereLaunch.sequence`).
    func applySummaryConfiguration() async {
        await services.summary.configure(enabled: summaryEnabled, time: summaryTime)
        notificationsAuthorized = await services.reminders.isAuthorized()
        if summaryEnabled, !notificationsAuthorized {
            if !warnedSummaryUnauthorized {
                Self.logger.warning("Daily summary enabled but notifications not authorized")
                warnedSummaryUnauthorized = true
            }
        } else {
            warnedSummaryUnauthorized = false
        }
    }

    public func clearSelectedYear() async {
        do {
            try await services.journal.clearYear(selectedYear)
            await refresh()
            await refreshDataIssues(force: true)
        } catch {
            loadState = .failed(error.localizedDescription)
            Self.logger.warning(
                "Failed to clear year \(selectedYear): \(error.localizedDescription)",
            )
        }
    }

    /// Erase all persisted data and reset this session's observable state to a
    /// clean slate. A thin pass-through to `WhereServices.reset()`, which owns
    /// *what* gets cleared (GPS stop + store wipe + reminder/badge reconcile +
    /// empty widget snapshot); the session only mirrors the outcome. The data
    /// half of the reset/erase teardown (see `WhereLaunch.resetSequence`);
    /// throws on persistence failure so the reset step parks the launcher in
    /// `.failed` rather than silently half-erasing.
    public func eraseSession() async throws {
        try await services.reset()
        isTracking = false
        report = nil
        dataIssues = []
        loadState = .idle
        Self.logger.info("Erased session and reset state")
    }

    // MARK: - Backup

    /// Where a backup export/import is in its lifecycle, so the UI can show a
    /// spinner and disable the relevant row while work is in flight.
    public enum BackupState: Equatable {
        case idle
        case exporting
        case importing
    }

    public private(set) var backupState: BackupState = .idle

    /// Fraction (`0...1`) of the in-flight import that has been written, for a
    /// determinate progress bar. Reset to `0` whenever an import isn't running.
    public private(set) var backupProgress: Double = 0

    /// Staging directory of the most recent export. The share sheet copies the
    /// file it needs out of our temporary directory, and `ShareLink` gives us
    /// no dismissal hook to clean up after, so the previous export is deleted
    /// lazily when the next one starts (bounding us to one stale archive).
    private var previousExportDirectory: URL?

    /// Last backup failure, surfaced as an alert. Mutable so the alert binding
    /// can clear it on dismiss (mirrors `permissionDenied`).
    public var backupError: String?

    /// Drives the backup-error alert. Reads `true` while `backupError` holds a
    /// message and clears it when the alert is dismissed, so the view can bind
    /// straight to it (`$session.isShowingBackupError`) instead of building a
    /// closure-based `Binding`. `backupError` stays the single source of truth.
    public var isShowingBackupError: Bool {
        get { backupError != nil }
        set { if !newValue { backupError = nil } }
    }

    /// Build a backup `.zip` of the entire database and return its URL for the
    /// share sheet, or `nil` if the export failed (in which case `backupError`
    /// is set). The caller is responsible for the returned temporary file.
    public func exportBackup() async -> URL? {
        if let previous = previousExportDirectory {
            try? FileManager.default.removeItem(at: previous)
            previousExportDirectory = nil
        }
        backupState = .exporting
        defer { backupState = .idle }
        do {
            let url = try await services.backup.exportBackup()
            previousExportDirectory = url.deletingLastPathComponent()
            Self.logger.info("Exported backup archive")
            return url
        } catch {
            backupError = error.localizedDescription
            Self.logger.warning("Backup export failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Import a backup file with the chosen merge/replace strategy, refreshing
    /// the current year afterward. Returns the import summary on success, or
    /// `nil` on failure (with `backupError` set).
    public func importBackup(
        from url: URL,
        strategy: BackupCoordinator.ImportStrategy,
    ) async -> BackupCoordinator.ImportSummary? {
        backupState = .importing
        backupProgress = 0
        defer {
            backupState = .idle
            backupProgress = 0
        }

        // The backup coordinator reports progress from its own executor; funnel
        // it through an ordered stream and apply it to `backupProgress` on the
        // main actor so SwiftUI sees in-order, hop-free updates.
        let (progress, continuation) = AsyncStream<Double>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await fraction in progress {
                self?.backupProgress = fraction
            }
        }
        defer { observer.cancel() }

        do {
            let summary = try await services.backup.importBackup(from: url, strategy: strategy) {
                continuation.yield($0)
            }
            continuation.finish()
            await observer.value
            await refresh()
            await refreshDataIssues(force: true)
            Self.logger.info(
                "Imported backup (\(summary.sampleCount) samples, \(summary.evidenceCount) evidence, \(summary.manualDayCount) manual days, \(summary.dismissedIssueCount) dismissals)",
            )
            return summary
        } catch {
            continuation.finish()
            backupError = error.localizedDescription
            Self.logger.warning("Backup import failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Drives the background-tracking `Toggle`. Reads the live `isTracking`
    /// state; assigning kicks off the matching async start/stop so the view can
    /// bind straight to it (`$session.trackingEnabled`) instead of building a
    /// closure-based `Binding`. `isTracking` stays the single source of truth.
    public var trackingEnabled: Bool {
        get { isTracking }
        set {
            Task { newValue ? await startTracking() : await stopTracking() }
        }
    }
}

#if DEBUG
    @_spi(Testing) extension WhereSession {
        /// Inject issues for previews/tests without seeding raw samples.
        public func setDataIssues(_ issues: [any DataIssue]) {
            dataIssues = issues
        }
    }

    extension WhereSession {
        /// A read-only SwiftData inspector over the live store, for the DEBUG-only
        /// developer entry point in Settings. `nil` when the backing store isn't
        /// SwiftData (e.g. a preview/test fake), so the entry point hides itself.
        var swiftDataInspectorConfiguration: SwiftDataInspectorConfiguration? {
            guard let container = services.modelContainer else { return nil }
            return SwiftDataInspectorConfiguration(
                container: container,
                modelTypes: SwiftDataStore.inspectorModelTypes,
                title: Strings.settingsDebugInspectorTitle,
            )
        }
    }
#endif
