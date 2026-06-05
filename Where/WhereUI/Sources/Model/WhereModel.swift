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

    private var controller: WhereController?
    private var authorizationTask: Task<Void, Never>?
    private let defaults: UserDefaults

    /// Persisted user intent to track in the background. Effective tracking is
    /// this AND `.always` authorization; we default to `true` so that, once the
    /// user grants Always, tracking resumes automatically on every launch.
    private var wantsTracking: Bool {
        get { defaults.object(forKey: Self.wantsTrackingKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.wantsTrackingKey) }
    }

    private static let wantsTrackingKey = "where.wantsBackgroundTracking"

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
    ) {
        self.selectedYear = selectedYear
        self.defaults = defaults
    }

    /// Preview/test seam: inject an already-built controller (and optionally a
    /// preloaded report) so SwiftUI previews and unit tests skip the live
    /// SwiftData + CoreLocation wiring.
    public init(
        controller: WhereController,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
        defaults: UserDefaults = .standard,
    ) {
        self.controller = controller
        self.report = report
        self.selectedYear = selectedYear
        self.defaults = defaults
        loadState = report == nil ? .idle : .loaded
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
        guard controller != nil else { return }
        await syncAuthorization()
        observeAuthorizationChanges()
        await reconcileTracking()
        await refresh()
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

    /// Last backup failure, surfaced as an alert. Mutable so the alert binding
    /// can clear it on dismiss (mirrors `permissionDenied`).
    public var backupError: String?

    /// Build a backup `.zip` of the entire database and return its URL for the
    /// share sheet, or `nil` if the export failed (in which case `backupError`
    /// is set). The caller is responsible for the returned temporary file.
    public func exportBackup() async -> URL? {
        guard let controller else { return nil }
        backupState = .exporting
        defer { backupState = .idle }
        do {
            return try await controller.exportBackup()
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
        defer { backupState = .idle }
        do {
            let summary = try await controller.importBackup(from: url, strategy: strategy)
            await refresh()
            return summary
        } catch {
            backupError = error.localizedDescription
            return nil
        }
    }
}
