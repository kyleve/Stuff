import Foundation
import Observation
import WhereCore

/// Observable view-model bridging the SwiftUI layer to the `WhereController`
/// actor. Owns the selected year, the loaded `YearReport`, and the GPS /
/// permission state, and funnels every mutation through the controller so the
/// views stay free of persistence and CoreLocation details.
@MainActor
@Observable
public final class WhereModel {
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

    /// Whether background GPS ingestion is currently attached. Reflects reality
    /// (authorization + the user's intent), not just the last button tap.
    public private(set) var isTracking = false

    /// The latest known location authorization status, kept live via
    /// `WhereController.authorizationUpdates()`.
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
            defaults.set(newValue, forKey: Self.remindersEnabledKey)
            Task { await applyReminderConfiguration() }
        }
    }

    /// Time of day the daily reminder fires. Persists and reconciles on change.
    public var reminderTime: ReminderTime {
        get { reminderTimeStorage }
        set {
            guard newValue != reminderTimeStorage else { return }
            reminderTimeStorage = newValue
            defaults.set(newValue.hour, forKey: Self.reminderHourKey)
            defaults.set(newValue.minute, forKey: Self.reminderMinuteKey)
            Task { await applyReminderConfiguration() }
        }
    }

    /// `Date`-typed projection of `reminderTime` for the Settings `DatePicker`,
    /// which works in `Date`. Lets the view bind `$model.reminderTimeOfDay`
    /// directly instead of building a closure binding; writes round-trip back
    /// into `reminderTime` (and its persistence/reconcile).
    public var reminderTimeOfDay: Date {
        get {
            Self.calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: now(),
            ) ?? now()
        }
        set {
            let components = Self.calendar.dateComponents([.hour, .minute], from: newValue)
            reminderTime = ReminderTime(
                hour: components.hour ?? ReminderTime.defaultEvening.hour,
                minute: components.minute ?? ReminderTime.defaultEvening.minute,
            )
        }
    }

    /// Observed backing storage for `remindersEnabled` / `reminderTime`. The
    /// public computed properties layer persistence + reconciliation onto their
    /// setters, which a stored property can't express.
    private var remindersEnabledStorage: Bool
    private var reminderTimeStorage: ReminderTime

    /// Whether the system has granted notification permission. Lets the Settings
    /// UI route the user to the system Settings app when they've enabled
    /// reminders but denied permission.
    public private(set) var notificationsAuthorized = false

    private var controller: WhereController?
    private var authorizationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    /// Persisted user intent to track in the background. Effective tracking is
    /// this AND `.always` authorization; we default to `true` so that, once the
    /// user grants Always, tracking resumes automatically on every launch.
    private var wantsTracking: Bool {
        get { defaults.object(forKey: Self.wantsTrackingKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.wantsTrackingKey) }
    }

    private static let wantsTrackingKey = "where.wantsBackgroundTracking"
    private static let remindersEnabledKey = "where.remindersEnabled"
    private static let reminderHourKey = "where.reminderHour"
    private static let reminderMinuteKey = "where.reminderMinute"

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
            through: MissingDays.backlogCutoff(asOf: now(), calendar: Self.calendar),
            present: present,
            calendar: Self.calendar,
        )
    }

    /// Total number of unlogged days behind `missingDays`.
    public var missingDayCount: Int {
        missingDays.reduce(0) { $0 + $1.dayCount }
    }

    private var isViewingCurrentYear: Bool {
        selectedYear == Self.calendar.component(.year, from: now())
    }

    /// Gregorian calendar in the current time zone — matches the day keys the
    /// aggregator produces in `report.days`, so the missing-day math lines up.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
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

    public static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    public init(
        selectedYear: Int = WhereModel.currentYear,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.selectedYear = selectedYear
        self.defaults = defaults
        self.now = now
        remindersEnabledStorage = Self.loadRemindersEnabled(from: defaults)
        reminderTimeStorage = Self.loadReminderTime(from: defaults)
    }

    /// Preview/test seam: inject an already-built controller (and optionally a
    /// preloaded report) so SwiftUI previews and unit tests skip the live
    /// SwiftData + CoreLocation wiring.
    public init(
        controller: WhereController,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.controller = controller
        self.report = report
        self.selectedYear = selectedYear
        self.defaults = defaults
        self.now = now
        remindersEnabledStorage = Self.loadRemindersEnabled(from: defaults)
        reminderTimeStorage = Self.loadReminderTime(from: defaults)
        loadState = report == nil ? .idle : .loaded
    }

    private static func loadRemindersEnabled(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: remindersEnabledKey) as? Bool ?? true
    }

    private static func loadReminderTime(from defaults: UserDefaults) -> ReminderTime {
        let hour = defaults.object(forKey: reminderHourKey) as? Int ?? ReminderTime.defaultEvening
            .hour
        let minute = defaults.object(forKey: reminderMinuteKey) as? Int
            ?? ReminderTime.defaultEvening.minute
        return ReminderTime(hour: hour, minute: minute)
    }

    /// Synchronously build the production controller (SwiftData +
    /// CoreLocation) if it doesn't exist yet. Idempotent.
    ///
    /// Constructing `CoreLocationSource` here creates the `CLLocationManager`
    /// and installs its delegate, which CoreLocation requires to happen early
    /// in app launch so it can deliver significant-change / visit events when
    /// the app is relaunched into the background after termination. The app
    /// delegate calls this from `didFinishLaunching`; `start()` also calls it
    /// to cover the preview/no-delegate path.
    public func bootstrap() {
        guard controller == nil else { return }
        do {
            let store = try SwiftDataStore.make()
            controller = WhereController(
                store: store,
                locationSource: CoreLocationSource(),
            )
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Ensure the controller exists, sync authorization, resume tracking if
    /// appropriate, then load the selected year. Safe to call repeatedly; the
    /// controller and the authorization observer are only set up once.
    public func start() async {
        bootstrap()
        guard let controller else { return }
        await syncAuthorization()
        observeAuthorizationChanges()
        await reconcileTracking()
        await refresh()
        await applyReminderConfiguration()
        // Republish the widget snapshot from whatever is already on disk so a
        // cold launch with no writes this session doesn't leave the widget
        // blank or showing the previous day's "today".
        await controller.refreshWidgetSnapshot()
    }

    /// Refresh state that can change while the app is away, including
    /// notification permission edits made in Settings and calendar-day rollover.
    public func appBecameActive() async {
        bootstrap()
        guard let controller else { return }
        await syncAuthorization()
        await reconcileTracking()
        await refresh()
        await applyReminderConfiguration()
        // The calendar day may have rolled over while backgrounded; recompute
        // so the widget's "today" reflects the current day rather than stale
        // foreground state.
        await controller.refreshWidgetSnapshot()
    }

    /// Read the current authorization status from the controller into our
    /// observable state. Does not surface the permission alert — that's
    /// reserved for explicit user actions.
    private func syncAuthorization() async {
        guard let controller else { return }
        authorizationStatus = await controller.authorizationStatus()
    }

    /// Subscribe to live authorization changes (prompt results, Settings-app
    /// edits) so the indicator and tracking state stay in sync. Idempotent.
    private func observeAuthorizationChanges() {
        guard authorizationTask == nil, let controller else { return }
        authorizationTask = Task { @MainActor [weak self] in
            let updates = await controller.authorizationUpdates()
            for await status in updates {
                guard let self else { break }
                authorizationStatus = status
                await reconcileTracking()
            }
        }
    }

    /// Start or stop GPS ingestion so it matches the user's intent and the
    /// current authorization. Tracking only runs with Always authorization.
    private func reconcileTracking() async {
        guard let controller else { return }
        if wantsTracking, authorizationStatus.allowsBackgroundTracking {
            await controller.startGPS()
            isTracking = true
        } else {
            await controller.stopGPS()
            isTracking = false
        }
    }

    public func select(year: Int) async {
        guard year != selectedYear else { return }
        selectedYear = year
        // Drop the previous year's report so views fall back to their loading
        // state instead of rendering stale data under the new year's label.
        report = nil
        await refresh()
    }

    public func refresh() async {
        guard let controller else { return }
        // Capture the year this fetch is for. `WhereModel` is reentrant while
        // awaiting `yearReport`, so a rapid second `select(year:)` can start a
        // newer fetch that finishes first; without this guard a slower older
        // fetch could install its report under the newer year's label.
        let requestedYear = selectedYear
        loadState = .loading
        do {
            let report = try await controller.yearReport(for: requestedYear)
            guard requestedYear == selectedYear else { return }
            self.report = report
            loadState = .loaded
        } catch {
            guard requestedYear == selectedYear else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Persist a single manual day. Throws on persistence failure so the
    /// caller (the entry form) can keep itself open and show the error inline
    /// instead of dismissing as if the save succeeded.
    public func setManualDay(date: Date, regions: Set<Region>) async throws {
        guard let controller else { return }
        try await controller.addManualDay(date: date, regions: regions)
        await refresh()
    }

    /// Persist a manual day range. Throws on persistence failure (see
    /// `setManualDay(date:regions:)`).
    public func setManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
    ) async throws {
        guard let controller else { return }
        try await controller.addManualDays(from: start, through: end, regions: regions)
        await refresh()
    }

    /// Authoritatively set a day's regions, *replacing* whatever was
    /// attributed to it (the Elsewhere "fix this day" path) rather than
    /// unioning. Throws on persistence failure so the editor can stay open and
    /// surface the error instead of dismissing as if the save succeeded.
    public func overrideDay(date: Date, regions: Set<Region>) async throws {
        guard let controller else { return }
        try await controller.overrideDay(date: date, regions: regions)
        await refresh()
    }

    /// Undo a day's manual override/backfill, restoring the GPS-detected
    /// regions (the relabel "reset to GPS" action). Throws on persistence
    /// failure so the editor can stay open and surface the error.
    public func clearManualDay(date: Date) async throws {
        guard let controller else { return }
        try await controller.clearManualDay(date: date)
        await refresh()
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
    /// Returns an empty array (rather than throwing) on failure or before the
    /// controller is wired up, so the view can simply render nothing.
    public func locations(in region: Region) async -> [RegionDayLocations] {
        guard let controller else { return [] }
        return await (try? controller.locations(in: region, year: selectedYear)) ?? []
    }

    /// One representative coordinate per region for the selected year (the
    /// most heavily sampled spot in each), for the Elsewhere cards' place-name
    /// teaser. Empty on failure or before the controller exists.
    public func representativeCoordinates() async -> [Region: Coordinate] {
        guard let controller else { return [:] }
        return await (try? controller.representativeCoordinates(for: selectedYear)) ?? [:]
    }

    /// Explicitly (re)request location access, e.g. from the "Grant location
    /// access" button. Drives the system prompt when possible, then syncs the
    /// status and reconciles tracking so the UI reflects the outcome.
    public func requestPermission() async {
        guard let controller else { return }
        do {
            try await controller.requestLocationPermission()
            permissionDenied = false
        } catch {
            // `.denied` / `.restricted` mean re-prompting won't help, so the UI
            // routes the user to the Settings app.
            permissionDenied = true
        }
        await syncAuthorization()
        await reconcileTracking()
    }

    /// Turn on background tracking. Records the intent, requests permission if
    /// needed, then reconciles — `isTracking` only flips on once Always
    /// authorization is in hand and GPS is actually running. When only
    /// When-In-Use is granted the indicator guides the user to Settings; on a
    /// hard denial the Settings alert is surfaced.
    public func startTracking() async {
        guard let controller else { return }
        wantsTracking = true
        do {
            try await controller.requestLocationPermission()
            permissionDenied = false
        } catch {
            permissionDenied = true
        }
        await syncAuthorization()
        await reconcileTracking()
    }

    public func stopTracking() async {
        guard let controller else { return }
        wantsTracking = false
        await controller.stopGPS()
        isTracking = false
    }

    /// Push the current reminder intent to the controller and refresh whether
    /// the system has granted notification permission.
    private func applyReminderConfiguration() async {
        guard let controller else { return }
        await controller.configureReminders(enabled: remindersEnabled, time: reminderTime)
        notificationsAuthorized = await controller.notificationAuthorizationGranted()
    }

    public func clearSelectedYear() async {
        guard let controller else { return }
        do {
            try await controller.clearYear(selectedYear)
            await refresh()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
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
    /// straight to it (`$model.isShowingBackupError`) instead of building a
    /// closure-based `Binding`. `backupError` stays the single source of truth.
    public var isShowingBackupError: Bool {
        get { backupError != nil }
        set { if !newValue { backupError = nil } }
    }

    /// Build a backup `.zip` of the entire database and return its URL for the
    /// share sheet, or `nil` if the export failed (in which case `backupError`
    /// is set). The caller is responsible for the returned temporary file.
    public func exportBackup() async -> URL? {
        guard let controller else { return nil }
        if let previous = previousExportDirectory {
            try? FileManager.default.removeItem(at: previous)
            previousExportDirectory = nil
        }
        backupState = .exporting
        defer { backupState = .idle }
        do {
            let url = try await controller.exportBackup()
            previousExportDirectory = url.deletingLastPathComponent()
            return url
        } catch {
            backupError = error.localizedDescription
            return nil
        }
    }

    /// Import a backup file with the chosen merge/replace strategy, refreshing
    /// the current year afterward. Returns the import summary on success, or
    /// `nil` on failure (with `backupError` set).
    public func importBackup(
        from url: URL,
        strategy: WhereController.ImportStrategy,
    ) async -> WhereController.ImportSummary? {
        guard let controller else { return nil }
        backupState = .importing
        backupProgress = 0
        defer {
            backupState = .idle
            backupProgress = 0
        }

        // The controller reports progress from its own executor; funnel it
        // through an ordered stream and apply it to `backupProgress` on the
        // main actor so SwiftUI sees in-order, hop-free updates.
        let (progress, continuation) = AsyncStream<Double>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await fraction in progress {
                self?.backupProgress = fraction
            }
        }
        defer { observer.cancel() }

        do {
            let summary = try await controller.importBackup(from: url, strategy: strategy) {
                continuation.yield($0)
            }
            continuation.finish()
            await observer.value
            await refresh()
            return summary
        } catch {
            continuation.finish()
            backupError = error.localizedDescription
            return nil
        }
    }

    /// Drives the background-tracking `Toggle`. Reads the live `isTracking`
    /// state; assigning kicks off the matching async start/stop so the view can
    /// bind straight to it (`$model.trackingEnabled`) instead of building a
    /// closure-based `Binding`. `isTracking` stays the single source of truth.
    public var trackingEnabled: Bool {
        get { isTracking }
        set {
            Task { newValue ? await startTracking() : await stopTracking() }
        }
    }
}
