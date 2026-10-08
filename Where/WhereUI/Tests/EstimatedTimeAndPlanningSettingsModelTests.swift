import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct EstimatedTimeAndPlanningSettingsModelTests {
    @Test func hidingAndShowingEstimatesPreservesEveryStayAndHome() async throws {
        let store = try TestStore()
        let preferences = makePreferences()
        let report = YearReportModel(
            services: PlanningModelTestSupport.services(store: store),
            selectedYear: 2026,
            preferences: preferences,
            now: { PlanningModelTestSupport.now },
        )
        let first = try PlanningModelTestSupport.stay(region: .newYork)
        let second = try PlanningModelTestSupport.stay(region: .california)
        try await report.forecasts.create(stay: first)
        try await report.forecasts.create(stay: second)
        try await report.forecasts.setHomeRegion(.california)
        await report.forecasts.refresh()
        let before = try await report.services.plannedStays.snapshot()
        await store.failPlannedStays()
        let model = EstimatedTimeAndPlanningSettingsModel(report: report)

        await model.setEnabled(false)
        #expect(!model.isEnabled)
        #expect(!preferences.showsEstimatedTimeAndPlanning)
        #expect(try await report.services.plannedStays.snapshot() == before)
        #expect(report.forecasts.planning == before)
        #expect(model.presentedFailure == nil)

        await model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(try await report.services.plannedStays.snapshot() == before)
    }
}
