import Foundation
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Covers `YearReportModel`: the year report load (out-of-order year fetches, failed
/// manual saves), the missing-day computation the banner / backfill read, the
/// Resolve badge count, and the store-change observer that keeps them honest.
@MainActor
struct YearReportModelTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    /// Build dates in the same calendar `YearReportModel` uses (gregorian, current
    /// time zone), so the day keys line up regardless of the host machine.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func cday(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    // MARK: - Year load / stale fetches / save errors

    @Test func staleYearFetchDoesNotOverwriteNewerSelection() async throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )

        // Seed each year with a distinct region so we can tell which report won.
        try await services.journal.addManualDay(
            date: date(year: 2024, month: 3, day: 1),
            regions: [.newYork],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
            audit: nil,
        )

        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )
        await store.enableFirstSamplesGate()

        // Start the 2024 fetch; it suspends inside the gated `samples(in:)`.
        let stale = Task { await report.select(year: 2024) }
        await store.awaitFirstSamplesCall()

        // The 2026 fetch runs to completion while 2024 is still in flight.
        await report.select(year: 2026)
        #expect(report.report?.year == 2026)

        // Now let the slower 2024 fetch finish — it must be discarded.
        await store.releaseFirstSamplesCall()
        await stale.value

        #expect(report.selectedYear == 2026)
        #expect(report.report?.year == 2026)
        #expect(report.report?.totals[.california] == 1)
        #expect(report.report?.totals[.newYork] == nil)
        #expect(report.loadState == .loaded)
    }

    @Test func failedManualSaveThrowsAndLeavesLoadStateAlone() async throws {
        let store = try TestStore()
        await store.failManualDays()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )

        await #expect(throws: ManualSaveFailure.self) {
            try await report.setManualDay(
                date: self.date(year: 2026, month: 1, day: 2),
                regions: [.california],
            )
        }

        // A failed save must not flip the whole screen into the error state;
        // the form surfaces the error inline instead.
        #expect(report.loadState == .idle)
    }

    @Test func failedManualRangeSaveThrows() async throws {
        let store = try TestStore()
        await store.failManualDays()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )

        await #expect(throws: ManualSaveFailure.self) {
            try await report.setManualDays(
                from: self.date(year: 2026, month: 1, day: 2),
                through: self.date(year: 2026, month: 1, day: 4),
                regions: [.california],
            )
        }
    }

    /// A failed year-report load parks `loadState` at `.failed(.reportUnavailable)`
    /// — the typed reason the error screens present — rather than a bare string.
    @Test func failedReportLoadParksInReportUnavailable() async throws {
        let store = try TestStore()
        await store.failSamples()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )

        await report.refresh()

        guard case let .failed(.reportUnavailable(message)) = report.loadState else {
            Issue.record("expected .failed(.reportUnavailable), got \(report.loadState)")
            return
        }
        #expect(!message.isEmpty)
    }

    // MARK: - Missing days

    @Test func missingDaysSurfacePastGapsAndExcludeToday() throws {
        let today = Self.day(2026, 1, 5)
        let present = [Self.day(2026, 1, 2), Self.day(2026, 1, 4)]
        let report = try YearReportModel(
            services: makeServices(),
            report: YearReport(
                year: 2026,
                days: present
                    .map { DayPresence(date: $0, in: Self.calendar, regions: [.california]) },
                totals: [.california: present.count],
            ),
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { today },
        )

        // Jan 1 and Jan 3 are past gaps. Jan 5 (today) is still loggable, so it
        // isn't surfaced even though it's unlogged.
        #expect(report.missingDays.map(\.start) == [
            Self.cday(2026, 1, 1),
            Self.cday(2026, 1, 3),
        ])
        #expect(report.missingDayCount == 2)
        #expect(!report.missingDays.contains { $0.start == Self.cday(2026, 1, 5) })
    }

    @Test func missingDaysAreEmptyWhenViewingAPastYear() throws {
        let today = Self.day(2026, 6, 1)
        let report = try YearReportModel(
            services: makeServices(),
            report: YearReport(year: 2025, days: [], totals: [:]),
            selectedYear: 2025,
            preferences: makePreferences(),
            now: { today },
        )

        #expect(report.missingDays.isEmpty)
        #expect(report.missingDayCount == 0)
    }

    // MARK: - Data-issue badge count

    @Test func refreshDataIssueCountCountsMissingDays() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )

        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
            audit: nil,
        )
        await report.refresh()
        await report.refreshDataIssueCount(force: true)

        #expect(report.dataIssueCount > 0)
    }

    @Test func driftThresholdChangePersists() throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let preferences = makePreferences()
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: preferences,
        )

        report.driftThreshold = .km25
        #expect(preferences.driftThresholdMeters == DriftThreshold.km25.rawValue)
    }

    /// The Resolve list keys its scan `.task(id:)` on `dataIssueScanInputs`, so a
    /// drift-threshold change must change that identity — otherwise the list keeps
    /// a stale scan while the badge count moves and the two visibly disagree. The
    /// mirror also has to be observable (it can't read straight through the
    /// non-observable `WherePreferences`) or a dependent view's `body` would never
    /// re-run to re-key the task.
    @Test func dataIssueScanInputsTrackTheDriftThreshold() throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let preferences = makePreferences()
        let report = YearReportModel(
            services: services,
            report: YearReport(year: 2026, days: [], totals: [:]),
            selectedYear: 2026,
            preferences: preferences,
        )

        let before = report.dataIssueScanInputs
        report.driftThreshold = .km25

        #expect(report.dataIssueScanInputs != before)
        #expect(report.dataIssueScanInputs.driftThreshold == .km25)
    }

    /// A manual "Find issues now" must re-key `dataIssueScanInputs` even though
    /// year / report / threshold are unchanged, so an already-open Resolve list
    /// reloads from the freshly-forced scan rather than keeping a stale one.
    @Test func rescanForIssuesRekeysScanInputs() async throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let report = YearReportModel(
            services: services,
            report: YearReport(year: 2026, days: [], totals: [:]),
            selectedYear: 2026,
            preferences: makePreferences(),
        )

        let before = report.dataIssueScanInputs
        await report.rescanForIssues()

        #expect(report.dataIssueScanInputs != before)
    }

    // MARK: - Store-change observer

    /// The write path no longer refreshes inline: a manual edit commits, the
    /// store pings `changes()`, and the data-change observer re-pulls the report
    /// + badge count. Proves the single read path keeps the UI honest.
    @Test func manualWriteRefreshesViaDataChangeObserver() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )

        // Observer only — no `refresh()` called here, so any state change must
        // arrive through the committed write's ping.
        report.observeDataChanges()
        #expect(report.report == nil)

        try await report.setManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
        )

        // The observer re-pulls the report first, then the badge count, so wait
        // for the *count* to land rather than just the report — otherwise this
        // races the two awaits and can read a stale 0 count between them.
        await waitUntil { report.report?.days.isEmpty == false && report.dataIssueCount > 0 }
        #expect(report.report?.days.isEmpty == false)
        #expect(report.dataIssueCount > 0)
    }

    /// Guards against a retain cycle through the long-lived data-change observer:
    /// it captures `[weak self]` and `deinit` cancels it, so dropping the last
    /// strong reference deallocates the model even while the task is parked in
    /// `for await` (a quiet store emits nothing on its own).
    @Test func deinitsWhileObservingDataChanges() throws {
        let store = try TestStore()
        weak var weakReport: YearReportModel?
        do {
            let services = WhereServices(
                store: store,
                locationSource: ScriptedLocationSource(),
                reminderScheduler: NoopLoggingReminderScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
            )
            let report = YearReportModel(
                services: services,
                selectedYear: 2026,
                preferences: makePreferences(),
            )
            weakReport = report
            report.observeDataChanges()
            #expect(weakReport != nil)
        }
        #expect(weakReport == nil)
    }

    // MARK: - Scene activate / deactivate (the background-rescan leak fix)

    /// `activate()` subscribes and pulls, so the scene shows fresh data the moment
    /// it appears and stays live for later writes without a second `activate()`.
    @Test func activatePullsFreshDataAndStaysLive() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
            audit: nil,
        )

        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        await report.activate()
        #expect(report.report?.days.count == 1)
        #expect(report.loadState == .loaded)

        // Still subscribed — a later committed write re-pulls on its own.
        try await report.setManualDay(
            date: date(year: 2026, month: 1, day: 2),
            regions: [.california],
        )
        await waitUntil { report.report?.days.count == 2 }
    }

    /// The leak fix: once the scene backgrounds, `deactivate()` cancels the
    /// subscription so a committed write drives no refresh. Proven against a live
    /// probe sharing the same store — both subscribe to the same fan-out, so by
    /// the time the probe reacts to the write the paused model has already seen
    /// (and ignored) the same ping.
    @Test func deactivateStopsRefreshingOnWrites() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )

        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        await report.activate()
        #expect(report.report?.days.count == 0)
        report.deactivate()

        let probe = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        await probe.activate()

        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
            audit: nil,
        )
        await waitUntil { probe.report?.days.count == 1 }

        // The paused model never re-pulled off the same signal.
        #expect(report.report?.days.count == 0)
    }

    /// Reactivating on foreground re-subscribes *and* pulls, so a write that
    /// landed while the scene was backgrounded (live GPS, a remote sync) is caught
    /// up — the deactivate/activate pair can't strand the UI on stale data.
    @Test func reactivatingAfterBackgroundPullsTheGap() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )

        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
            now: { now },
        )
        await report.activate()
        #expect(report.report?.days.count == 0)
        report.deactivate()

        // A write while "backgrounded" — the paused model can't observe it.
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
            audit: nil,
        )
        #expect(report.report?.days.count == 0)

        // Foregrounding re-subscribes and pulls the gap.
        await report.activate()
        #expect(report.report?.days.count == 1)
    }

    // MARK: - Evidence day keys

    /// `activate()` loads the evidence day-keys the calendar badge reads, keyed
    /// to the capture day (in the model's calendar).
    @Test func activateLoadsEvidenceDayKeys() async throws {
        let services = try makeServices()
        let captured = date(year: 2026, month: 3, day: 4)
        try await services.journal.addEvidence(
            Evidence(kind: .planeTicket, capturedAt: captured, contentType: .pdf),
            blob: nil,
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )

        await report.activate()

        #expect(report.evidenceDayKeys == [Self.cday(2026, 3, 4)])
    }

    /// Adding evidence pings the store-change signal, so the observer re-pulls
    /// the day-keys without an explicit refresh — the calendar lights up on its
    /// own.
    @Test func addingEvidenceRefreshesDayKeysViaObserver() async throws {
        let services = try makeServices()
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )
        report.observeDataChanges()

        try await services.journal.addEvidence(
            Evidence(
                kind: .document,
                capturedAt: date(year: 2026, month: 7, day: 9),
                contentType: .pdf,
            ),
            blob: nil,
        )

        await waitUntil { report.evidenceDayKeys == [Self.cday(2026, 7, 9)] }
    }

    /// Switching years clears the previous year's markers immediately so the
    /// calendar can't badge the new year's days with the old year's evidence.
    @Test func selectingYearClearsEvidenceDayKeys() async throws {
        let services = try makeServices()
        try await services.journal.addEvidence(
            Evidence(
                kind: .photo,
                capturedAt: date(year: 2026, month: 5, day: 2),
                contentType: .image,
            ),
            blob: nil,
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )
        await report.activate()
        #expect(report.evidenceDayKeys == [Self.cday(2026, 5, 2)])

        await report.select(year: 2025)
        #expect(report.evidenceDayKeys.isEmpty)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "condition was not met before timeout")
    }
}
