import Foundation
import Testing
import WhereCore
@testable import WhereUI

/// Covers `WhereModel`'s refresh/save error handling that the PR review bots
/// flagged: out-of-order year fetches must not install stale data, and a
/// failed manual save must surface as an error rather than silently
/// "succeeding".
@MainActor
struct WhereModelRefreshTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    @Test func staleYearFetchDoesNotOverwriteNewerSelection() async throws {
        let store = try TestStore()
        let controller = WhereController(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )

        // Seed each year with a distinct region so we can tell which report won.
        try await controller.addManualDay(
            date: date(year: 2024, month: 3, day: 1),
            regions: [.newYork],
        )
        try await controller.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
        )

        let model = WhereModel(controller: controller, selectedYear: 2026)
        await store.enableFirstSamplesGate()

        // Start the 2024 fetch; it suspends inside the gated `samples(in:)`.
        let stale = Task { await model.select(year: 2024) }
        await store.awaitFirstSamplesCall()

        // The 2026 fetch runs to completion while 2024 is still in flight.
        await model.select(year: 2026)
        #expect(model.report?.year == 2026)

        // Now let the slower 2024 fetch finish — it must be discarded.
        await store.releaseFirstSamplesCall()
        await stale.value

        #expect(model.selectedYear == 2026)
        #expect(model.report?.year == 2026)
        #expect(model.report?.totals[.california] == 1)
        #expect(model.report?.totals[.newYork] == nil)
        #expect(model.loadState == .loaded)
    }

    @Test func failedManualSaveThrowsAndLeavesLoadStateAlone() async throws {
        let store = try TestStore()
        await store.failManualDays()
        let controller = WhereController(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let model = WhereModel(controller: controller, selectedYear: 2026)

        await #expect(throws: ManualSaveFailure.self) {
            try await model.setManualDay(
                date: self.date(year: 2026, month: 1, day: 2),
                regions: [.california],
            )
        }

        // A failed save must not flip the whole screen into the error state;
        // the form surfaces the error inline instead.
        #expect(model.loadState == .idle)
    }

    @Test func failedManualRangeSaveThrows() async throws {
        let store = try TestStore()
        await store.failManualDays()
        let controller = WhereController(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let model = WhereModel(controller: controller, selectedYear: 2026)

        await #expect(throws: ManualSaveFailure.self) {
            try await model.setManualDays(
                from: self.date(year: 2026, month: 1, day: 2),
                through: self.date(year: 2026, month: 1, day: 4),
                regions: [.california],
            )
        }
    }

    // MARK: - Widget snapshot republishing on launch / activation

    /// The widget extension only reads the published snapshot file, so opening
    /// the app with data already on disk must republish — otherwise the widget
    /// stays blank/stale until the next write.
    @Test func startPublishesWidgetSnapshotFromExistingData() async throws {
        let (model, refresher) = try await makePublishingModel()
        await model.start()
        #expect(await refresher.publishCount == 1)
        #expect(await refresher.lastSnapshot?.totals == [.california: 1])
    }

    /// Returning to the foreground (e.g. on a new calendar day) recomputes and
    /// republishes too.
    @Test func appBecameActiveRepublishesWidgetSnapshot() async throws {
        let (model, refresher) = try await makePublishingModel()
        await model.appBecameActive()
        #expect(await refresher.publishCount == 1)
        #expect(await refresher.lastSnapshot?.totals == [.california: 1])
    }

    /// A model whose controller already holds one California day (seeded
    /// straight into the store so nothing is published yet), wired to a spy
    /// refresher and a fixed "now" so the year report is deterministic.
    private func makePublishingModel() async throws -> (WhereModel, SpyWidgetRefresher) {
        let store = try TestStore()
        // Seed straight into the store (inside `perform`, as the store
        // requires) so nothing is published before the model's lifecycle hook.
        let seed = DayPresence(date: date(year: 2026, month: 3, day: 1), regions: [.california])
        try await store.perform { try await store.setManualDay(seed) }
        let refresher = SpyWidgetRefresher()
        let now = date(year: 2026, month: 3, day: 15)
        let controller = WhereController(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: refresher,
            now: { now },
        )
        return (WhereModel(controller: controller, selectedYear: 2026), refresher)
    }
}

/// Captures the snapshots published through the controller so the model's
/// launch/activation hooks can be checked for republishing widget data.
private actor SpyWidgetRefresher: WidgetTimelineRefreshing {
    private(set) var publishedSnapshots: [WidgetSnapshot] = []

    var publishCount: Int {
        publishedSnapshots.count
    }

    var lastSnapshot: WidgetSnapshot? {
        publishedSnapshots.last
    }

    func publish(_ snapshot: WidgetSnapshot) async {
        publishedSnapshots.append(snapshot)
    }
}
