import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarModelTests {
    @Test func preferencesRemainIndependentAcrossRecreationAndYearChanges() async {
        let report = PreviewSupport.loadedYearReportModel()
        let california = CalendarModel(report: report, persistenceKey: .region(.california))
        let newYork = CalendarModel(report: report, persistenceKey: .region(.newYork))
        california.setOverview(true)
        newYork.setOverview(false)
        #expect(CalendarModel(report: report, persistenceKey: .region(.california))
            .isOverview(fallback: false))
        await report.select(year: report.selectedYear - 1)
        #expect(california.isOverview(fallback: false))
        #expect(!newYork.isOverview(fallback: true))
        let sessionOnly = CalendarModel(report: report, persistenceKey: nil)
        sessionOnly.setOverview(true)
        #expect(!sessionOnly.isOverview(fallback: false))
    }

    @Test func overviewAvailabilityMatchesDetailedPlanningVisibility() throws {
        let report = PreviewSupport.plannedStayYearReportModel()
        let yearReport = try #require(report.report)
        let months = try yearReport.calendarMonths(
            calendar: report.calendar,
            referenceDate: report.referenceDate,
            flightDays: [],
        )
        let visible = CalendarModel.visibleMonths(
            months,
            report: report,
            focusedRegion: nil,
        )
        #expect(months.count == 12)
        #expect(visible.contains { $0.month > 7 })
        let hidden = PreviewSupport.plannedStayYearReportModel(showsEstimatedTimeAndPlanning: false)
        let hiddenMonths = CalendarModel.visibleMonths(
            months,
            report: hidden,
            focusedRegion: nil,
        )
        #expect(hiddenMonths.map(\.month) == Array(1 ... 7))
    }
}
