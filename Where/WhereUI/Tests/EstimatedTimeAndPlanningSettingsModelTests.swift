import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct EstimatedTimeAndPlanningSettingsModelTests {
    @Test func disablingClearsThePlanBeforePersistingOff() async throws {
        let store = try TestStore()
        let preferences = makePreferences()
        let report = makeReport(store: store, preferences: preferences)
        try await report.forecasts.set(
            region: .california,
            through: CalendarDay(year: 2027, month: 1, day: 1).startOfDay(in: report.calendar),
        )
        let model = EstimatedTimeAndPlanningSettingsModel(report: report)

        await model.setEnabled(false)

        #expect(model.isEnabled == false)
        #expect(preferences.showsEstimatedTimeAndPlanning == false)
        #expect(report.forecasts.activePlannedStay == nil)
        #expect(try await report.services.plannedStays.active() == nil)
    }

    @Test func failedClearLeavesTheFeatureOnAndPresentsTheFailure() async throws {
        let store = try TestStore()
        let preferences = makePreferences()
        let report = makeReport(store: store, preferences: preferences)
        try await report.forecasts.set(
            region: .california,
            through: CalendarDay(year: 2027, month: 1, day: 1).startOfDay(in: report.calendar),
        )
        await store.failPlannedStays()
        let model = EstimatedTimeAndPlanningSettingsModel(report: report)

        await model.setEnabled(false)

        #expect(model.isEnabled)
        #expect(preferences.showsEstimatedTimeAndPlanning)
        #expect(report.forecasts.activePlannedStay?.region == .california)
        #expect(model.presentedFailure != nil)
    }

    @Test func enablingDoesNotCreateAPlan() async throws {
        let store = try TestStore()
        let preferences = makePreferences()
        preferences.showsEstimatedTimeAndPlanning = false
        let report = makeReport(store: store, preferences: preferences)
        let model = EstimatedTimeAndPlanningSettingsModel(report: report)

        await model.setEnabled(true)

        #expect(model.isEnabled)
        #expect(preferences.showsEstimatedTimeAndPlanning)
        #expect(try await report.services.plannedStays.active() == nil)
    }

    private func makeReport(
        store: TestStore,
        preferences: WherePreferences,
    ) -> YearReportModel {
        YearReportModel(
            services: WhereServices(
                store: store,
                locationSource: ScriptedLocationSource(),
                reminderScheduler: NoopLoggingReminderScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
            ),
            selectedYear: 2026,
            preferences: preferences,
        )
    }
}
