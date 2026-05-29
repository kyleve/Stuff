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
        let controller = WhereController(store: store, locationSource: ScriptedLocationSource())

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
        let controller = WhereController(store: store, locationSource: ScriptedLocationSource())
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
        let controller = WhereController(store: store, locationSource: ScriptedLocationSource())
        let model = WhereModel(controller: controller, selectedYear: 2026)

        await #expect(throws: ManualSaveFailure.self) {
            try await model.setManualDays(
                from: self.date(year: 2026, month: 1, day: 2),
                through: self.date(year: 2026, month: 1, day: 4),
                regions: [.california],
            )
        }
    }
}
