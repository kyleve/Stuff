import Foundation
import Observation
import PeriscopeCore
import RegionKit
import WhereCore

/// The scene-scoped presentation model for the selected year: the loaded
/// `YearReport` and everything derived from it (ranking, missing days, the
/// calendar inputs), the day-write intents, and the data-issue *count* the
/// Resolve tab badge reads.
///
/// Unlike `WhereSession` — the always-on coordinator that lives for the whole
/// logged-in lifetime — a `YearReportModel` is created by `MainTabs` only once the
/// real UI is on screen (the launch's `.ready` state) and torn down with it. It
/// owns the store's data-change subscription, started on scene `.active`
/// (`activate()`) and cancelled on background (`deactivate()`), so a headless
/// background relaunch never drives a `refresh()` no UI consumes.
///
/// `services` / `preferences` / `now` / `calendar` are exposed so the
/// view-scoped models a tab builds (`BackupModel`, `RemindersSettingsModel`,
/// `ResolveModel`) can be constructed from the injected `report` without also
/// threading the coordinator through.
@MainActor
@Observable
public final class YearReportModel {
    /// Where the current year's data is in its load lifecycle.
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// Carries a typed reason (see `LoadError`) rather than a bare message,
        /// so a caller can branch on *what* failed and tests can match the case.
        case failed(LoadError)
    }

    /// Why the selected year's data isn't available. Holds the underlying
    /// failure's user-presentable `message` as a `String` (not `any Error`) so
    /// `LoadState` stays `Equatable` for the refresh guards and tests, while
    /// still naming which operation failed.
    public enum LoadError: Error, Equatable {
        /// Loading the year report failed.
        case reportUnavailable(message: String)
        /// Clearing the selected year failed.
        case clearFailed(message: String)

        /// The underlying failure's user-presentable description.
        public var message: String {
            switch self {
                case let .reportUnavailable(message), let .clearFailed(message):
                    message
            }
        }
    }

    /// Identity of the inputs a data-issue scan depends on; see
    /// `dataIssueScanInputs`.
    struct DataIssueScanInputs: Equatable {
        let year: Int
        let report: YearReport?
        let driftThreshold: DriftThreshold
        /// Bumped by `rescanForIssues()` so a manual "Find issues now" re-keys
        /// the inputs and reloads the Resolve list even when nothing else
        /// (year / report / threshold) changed.
        let manualScanToken: Int
    }

    /// Incremented by `rescanForIssues()`; folded into `dataIssueScanInputs` so a
    /// forced rescan reloads the Resolve list. Observed (so the `.task(id:)`
    /// re-fires), never persisted.
    private var manualScanToken = 0

    public private(set) var selectedYear: Int
    public private(set) var report: YearReport?
    public private(set) var loadState: LoadState = .idle

    /// Start-of-day keys for days in the selected year that carry at least one
    /// piece of evidence. Refreshed alongside the report on every committed
    /// write (so a newly added attachment lights up its day), and fed into the
    /// calendar's `hasEvidence` day badge. Evidence is metadata only, so this is
    /// tracked separately from `report` (which drives residency).
    public private(set) var evidenceDayKeys: Set<CalendarDay> = []

    /// Unresolved data-issue count for the selected year — the Resolve tab badge.
    /// The full issue list lives on the view-scoped `ResolveModel`; only this
    /// count is kept here because the badge must render before the Resolve tab
    /// is ever materialized.
    public private(set) var dataIssueCount = 0

    /// The services every read/write funnels through. Exposed so sibling
    /// view-scoped models can be built from the injected `report`.
    let services: WhereServices
    /// Persisted user intent. Exposed for the same reason as `services`.
    let preferences: WherePreferences
    /// The model's notion of "now", forwarded for calendar / missing-day math.
    let now: @Sendable () -> Date

    /// Gregorian calendar in the current time zone — matches the day keys the
    /// aggregator produces in `report.days`, so the missing-day math lines up.
    let calendar: Calendar
    /// Synced planned-stay state and pure forecast projections for the
    /// Locations surfaces.
    let forecasts: LocationForecastModel

    /// Long-lived subscription to `services.dataChangeUpdates()` while the scene
    /// is active. `@ObservationIgnored` (plumbing, not UI state) and
    /// `nonisolated(unsafe)` so `deinit` can cancel it; every other access is on
    /// the main actor, and `deinit` runs with no other live references.
    @ObservationIgnored private nonisolated(unsafe) var dataChangeTask: Task<Void, Never>?

    private static let logger = WhereLog.session(YearReportModelLog.self)

    /// Observed mirror of `preferences.driftThresholdMeters`, which isn't itself
    /// observable (`WherePreferences` is a plain defaults wrapper — callers that
    /// need observation mirror it). Kept in sync by the `driftThreshold` setter so
    /// a change re-evaluates dependent views' `body`; without it `ResolutionView`
    /// couldn't key its scan on the threshold and the Resolve list would drift out
    /// of sync with the badge count.
    private var driftThresholdStorage: DriftThreshold

    /// Observed mirror of the Locations tab's forecast-visibility preference.
    /// `WherePreferences` is intentionally not observable, so Settings writes
    /// through this property to update the mounted Locations tab immediately.
    public var showsLocationForecastsOnLocationsTab: Bool {
        didSet {
            guard oldValue != showsLocationForecastsOnLocationsTab else { return }
            preferences.showsLocationForecastsOnLocationsTab =
                showsLocationForecastsOnLocationsTab
        }
    }

    /// GPS border-drift detection threshold (device setting). The setter persists
    /// it, forces a badge recount, and — through the observed mirror — re-keys
    /// `dataIssueScanInputs` so the Resolve list re-scans immediately, not just on
    /// its next unrelated load. The scanner cache is keyed by `(year, threshold)`,
    /// so the recount and the list both recompute for the new threshold no matter
    /// which of the two concurrent scans runs first.
    public var driftThreshold: DriftThreshold {
        get { driftThresholdStorage }
        set {
            guard newValue != driftThresholdStorage else { return }
            driftThresholdStorage = newValue
            preferences.driftThresholdMeters = newValue.rawValue
            Task { await refreshDataIssueCount(force: true) }
        }
    }

    /// The inputs that determine a data-issue scan's result: the selected year,
    /// the loaded report (any committed write re-pulls it; a year switch nils
    /// then reloads it), and the drift threshold. `ResolutionView` keys its scan
    /// `.task(id:)` on this, so the Resolve list re-scans on exactly the triggers
    /// the badge count recomputes on — the two can't drift apart.
    var dataIssueScanInputs: DataIssueScanInputs {
        DataIssueScanInputs(
            year: selectedYear,
            report: report,
            driftThreshold: driftThreshold,
            manualScanToken: manualScanToken,
        )
    }

    /// Primary/secondary split of the current report, or an empty ranking while
    /// nothing is loaded.
    public var ranking: RegionRanking {
        guard let report else { return RegionRanking(primary: [], secondary: []) }
        return RegionRanking(report: report)
    }

    /// Total distinct days with any tracked presence in the loaded year.
    public var trackedDayCount: Int {
        report?.days.count ?? 0
    }

    /// Unlogged days this year (Jan 1 through today), collapsed into ranges, for
    /// the warning banner and the backfill flow. Empty unless viewing the
    /// current year, since past years can't gain "today" coverage. The
    /// derivation lives on `YearReport`; this just supplies "now" + the calendar.
    public var missingDays: [MissingDayRange] {
        report?.missingDayRanges(asOf: now(), calendar: calendar) ?? []
    }

    /// Total number of unlogged days behind `missingDays`.
    public var missingDayCount: Int {
        report?.missingDayCount(asOf: now(), calendar: calendar) ?? 0
    }

    /// The model's notion of "now", forwarded for calendar and missing-day math.
    public var referenceDate: Date {
        now()
    }

    /// Calendar days that still need logging in the loaded year.
    public var missingDayKeys: Set<CalendarDay> {
        report?.missingDayKeys(asOf: now(), calendar: calendar) ?? []
    }

    /// Number of calendar days in the selected year (365, or 366 in a leap
    /// year). Region cards scale their ambient progress bar against this.
    public var daysInSelectedYear: Int {
        calendar.dayCount(ofYear: selectedYear)
    }

    /// Build a report model over an already-assembled service layer. `report` is
    /// the preview/test seam: a non-nil value lands `loadState` at `.loaded` so
    /// `#Preview`s render content synchronously without driving `activate()`.
    public init(
        services: WhereServices,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
        preferences: WherePreferences,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.services = services
        self.report = report
        self.selectedYear = selectedYear
        self.preferences = preferences
        self.now = now
        showsLocationForecastsOnLocationsTab =
            preferences.showsLocationForecastsOnLocationsTab
        driftThresholdStorage = DriftThreshold(rawValue: preferences.driftThresholdMeters)
            ?? .default
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        forecasts = LocationForecastModel(services: services, calendar: calendar, now: now)
        loadState = report == nil ? .idle : .loaded
    }

    deinit {
        dataChangeTask?.cancel()
    }

    /// Start observing committed writes and pull fresh data. Called by `MainTabs`
    /// when the scene becomes active. Safe to call repeatedly — the subscription
    /// is set up at most once until `deactivate()`.
    public func activate() async {
        observeDataChanges()
        await refreshAll(forceDataIssueCount: false)
    }

    /// Stop observing committed writes. Called by `MainTabs` when the scene goes
    /// to the background, so a backgrounded scene drives no refreshes; the next
    /// `activate()` re-subscribes and pulls (covering the background→foreground
    /// gap).
    public func deactivate() {
        dataChangeTask?.cancel()
        dataChangeTask = nil
    }

    /// Subscribe to the store's data-change signal so the report and the badge
    /// count refresh on any committed write — live GPS ingestion, CloudKit
    /// remote imports, and the scene's own edits. Idempotent.
    func observeDataChanges() {
        guard dataChangeTask == nil else { return }
        // Subscribe synchronously, before spawning the loop, so a write that
        // commits the instant after this returns can't slip its ping in ahead of
        // the subscription.
        let updates = services.dataChangeUpdates()
        dataChangeTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard let self else { break }
                await refreshAll(forceDataIssueCount: true)
            }
        }
    }

    public func select(year: Int) async {
        guard year != selectedYear else { return }
        Self.logger { .selectedYear(year: year) }
        selectedYear = year
        // Drop the previous year's report so views fall back to their loading
        // state instead of rendering stale data under the new year's label.
        report = nil
        // Clear the previous year's evidence markers too, so the calendar can't
        // briefly badge the new year's days with the old year's evidence.
        evidenceDayKeys = []
        await refreshAll(forceDataIssueCount: true)
    }

    /// Pull a fresh year report *and* recompute the Resolve badge count — the
    /// common case after any committed write or a (re)activation. `refresh()`
    /// and `refreshDataIssueCount(force:)` stay separately callable rather than
    /// folded together, because the drift-threshold change recomputes only the
    /// count (no report re-pull); this just names the pairing the shared sites use.
    func refreshAll(forceDataIssueCount: Bool) async {
        await Self.logger.measure(.sceneRefresh, budget: .seconds(3)) {
            await refresh()
            await refreshEvidenceDayKeys()
            await refreshDataIssueCount(force: forceDataIssueCount)
            await forecasts.refresh()
        }
    }

    /// Reload the set of days carrying evidence for the selected year. Runs on
    /// the same triggers as `refresh()` (activate, year switch, any committed
    /// write), so an added/removed attachment updates the calendar badge without
    /// a bespoke signal. Keeps the last good value and logs on failure rather
    /// than blanking the markers.
    func refreshEvidenceDayKeys() async {
        // Capture the year this load is for; the model is reentrant while
        // awaiting, so a concurrent `select(year:)` could otherwise install
        // keys under the wrong year's label.
        let requestedYear = selectedYear
        do {
            let keys = try await services.evidence.dayKeys(for: requestedYear)
            guard requestedYear == selectedYear else { return }
            if evidenceDayKeys != keys { evidenceDayKeys = keys }
        } catch {
            Self.logger {
                .evidenceDayKeysLoadFailed(
                    year: requestedYear,
                    description: error.localizedDescription,
                )
            }
        }
    }

    /// Force a fresh data-issue scan past the ~3h throttle — the Settings "Find
    /// issues now" action. Recomputes the badge with `force: true` (which also
    /// refreshes the scanner's shared cache), then re-keys `dataIssueScanInputs`
    /// so an already-open Resolve list reloads from that now-fresh cache too.
    /// This mirrors the dual refresh a drift-threshold change performs.
    public func rescanForIssues() async {
        await refreshDataIssueCount(force: true)
        manualScanToken += 1
    }

    /// Recompute the Resolve badge count for the selected year. Uses the cached
    /// scan (shared with the Resolve list) unless `force`.
    func refreshDataIssueCount(force: Bool) async {
        // Capture the year this scan is for; the model is reentrant while
        // awaiting, so a concurrent `select(year:)` could otherwise install a
        // count under the wrong year's label.
        let requestedYear = selectedYear
        do {
            let issues = try await services.resolution.issues(
                year: requestedYear,
                primaryRegions: ranking.primary.map(\.region),
                // Read the observable mirror (same value the `dataIssueScanInputs`
                // key the Resolve list scans on uses), so the badge recount and
                // the list can't scan against different thresholds.
                driftThresholdMeters: Double(driftThreshold.rawValue),
                force: force,
            )
            guard requestedYear == selectedYear else { return }
            if dataIssueCount != issues.count { dataIssueCount = issues.count }
        } catch {
            // Surface the failure and keep the last good count rather than
            // silently blanking the badge.
            Self.logger { .dataIssueScanFailed(description: error.localizedDescription) }
        }
    }

    public func refresh() async {
        // Capture the year this fetch is for; the model is reentrant while
        // awaiting `yearReport`, so a rapid second `select(year:)` could install
        // a stale report under the newer year's label.
        let requestedYear = selectedYear
        // Only surface the loading state when there's nothing on screen yet — an
        // initial load or a year switch (which nils `report` first). A background
        // refresh keeps the current report visible (no spinner flicker), and the
        // equality guards below make an unrelated commit a no-op.
        if report == nil { loadState = .loading }
        do {
            let report = try await services.reports.yearReport(for: requestedYear)
            guard requestedYear == selectedYear else { return }
            let changed = self.report != report
            if changed { self.report = report }
            if loadState != .loaded { loadState = .loaded }
            if changed {
                Self.logger {
                    .reportLoaded(year: requestedYear, dayCount: report.days.count)
                }
            }
        } catch {
            guard requestedYear == selectedYear else { return }
            loadState = .failed(.reportUnavailable(message: error.localizedDescription))
            Self.logger {
                .reportLoadFailed(year: requestedYear, description: error.localizedDescription)
            }
        }
    }

    /// Persist a single manual day. Throws on persistence failure so the caller
    /// (the entry form) can keep itself open and show the error inline.
    ///
    /// Captures an audit trail (`note` + best-effort capture-time GPS) for the
    /// entry. No inline refresh: the committed write pings the store-change
    /// signal, so `observeDataChanges()` re-pulls the report + badge count.
    public func setManualDay(date: Date, regions: Set<Region>, note: String? = nil) async throws {
        let audit = await makeEntryAudit(note: note)
        try await services.journal.addManualDay(date: date, regions: regions, audit: audit)
    }

    /// Persist a manual day range. Throws on persistence failure (see
    /// `setManualDay(date:regions:note:)`). One audit stamps the whole range.
    public func setManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
        note: String? = nil,
    ) async throws {
        let audit = await makeEntryAudit(note: note)
        try await services.journal.addManualDays(
            from: start,
            through: end,
            regions: regions,
            audit: audit,
        )
    }

    /// Authoritatively set a day's regions, *replacing* whatever was attributed
    /// to it (the Elsewhere "fix this day" path). Throws on persistence failure.
    /// Captures an audit trail (`note` + best-effort capture-time GPS).
    public func overrideDay(date: Date, regions: Set<Region>, note: String? = nil) async throws {
        let audit = await makeEntryAudit(note: note)
        try await services.journal.overrideDay(date: date, regions: regions, audit: audit)
    }

    /// Assemble the audit trail for a manual entry: stamp "now", normalize the
    /// note (blank/whitespace becomes `nil`), and attach a best-effort one-shot
    /// GPS fix for where the entry was made. A missing fix is recorded honestly
    /// (`location == nil`) rather than blocking the entry.
    private func makeEntryAudit(note: String?) async -> ManualEntryAudit {
        let sample = await services.ingestor.currentLocation()
        let location = sample.map { sample in
            CapturedLocation(
                coordinate: sample.coordinate,
                horizontalAccuracy: sample.horizontalAccuracy,
                timestamp: sample.timestamp,
            )
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ManualEntryAudit(
            recordedAt: now(),
            note: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            location: location,
        )
    }

    /// Undo a day's manual override/backfill, restoring the GPS-detected regions
    /// (the relabel "reset to GPS" action). Throws on persistence failure.
    public func clearManualDay(date: Date) async throws {
        try await services.journal.clearManualDay(date: date)
    }

    /// Undo several days' manual overlays in one transaction (the logged-days
    /// list's delete). Throws on persistence failure so the caller can surface
    /// it; the committed write pings the store-change signal, so observers
    /// re-pull without an inline refresh.
    public func clearManualDays(dates: [Date]) async throws {
        try await services.journal.clearManualDays(dates: dates)
    }

    public func clearSelectedYear() async {
        do {
            // The committed write pings the store-change signal, so
            // `observeDataChanges()` re-pulls; no inline refresh needed.
            try await services.journal.clearYear(selectedYear)
        } catch {
            loadState = .failed(.clearFailed(message: error.localizedDescription))
            Self.logger {
                .clearYearFailed(year: selectedYear, description: error.localizedDescription)
            }
        }
    }

    /// The days in the loaded report whose presence includes `region`, sorted
    /// ascending (matching `report.days`). Powers the Elsewhere drill-in list.
    public func days(in region: Region) -> [DayPresence] {
        guard let report else { return [] }
        return report.days.filter { $0.regions.contains(region) }
    }

    /// The raw coordinates recorded inside `region` during the selected year,
    /// grouped by day, for the Elsewhere drill-in's map and place names. Logs and
    /// returns empty on failure — the view renders nothing, but the failure still
    /// surfaces in the log rather than passing silently as "no locations".
    public func locations(in region: Region) async -> [RegionDayLocations] {
        do {
            return try await services.reports.locations(in: region, year: selectedYear)
        } catch {
            Self.logger {
                .locationsLoadFailed(
                    region: region.rawValue,
                    year: selectedYear,
                    description: error.localizedDescription,
                )
            }
            return []
        }
    }

    /// The recorded points for a single calendar `day`, grouped by attributed
    /// region, for the "Fix this day" screen and flight-day detail view maps.
    /// Logs and returns empty on failure (see `locations(in:)`).
    public func locations(onDay day: CalendarDay) async -> [Region: [RegionDayPoint]] {
        do {
            return try await services.reports.locations(onDay: day)
        } catch {
            Self.logger(attachments: [.error(error, name: "day-locations-error")]) {
                .dayLocationsLoadFailed(
                    day: day.description,
                    year: selectedYear,
                    description: error.localizedDescription,
                )
            }
            return [:]
        }
    }

    /// One representative coordinate per region for the selected year (the most
    /// heavily sampled spot in each), for the Elsewhere cards' place-name teaser.
    /// Logs and returns empty on failure (see `locations(in:)`).
    public func representativeCoordinates() async -> [Region: Coordinate] {
        do {
            return try await services.reports.representativeCoordinates(for: selectedYear)
        } catch {
            Self.logger {
                .representativeCoordinatesLoadFailed(
                    year: selectedYear,
                    description: error.localizedDescription,
                )
            }
            return [:]
        }
    }
}

#if DEBUG
    @_spi(Testing) extension YearReportModel {
        /// Inject a badge count for previews/tests without seeding raw samples.
        public func setDataIssueCount(_ count: Int) {
            dataIssueCount = count
        }
    }
#endif
