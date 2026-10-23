import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarPresentationModelTests {
    private func month(_ number: Int, year: Int = 2026) -> CalendarDay {
        CalendarDay(year: year, month: number, day: 1)
    }

    private func model() -> CalendarPresentationModel {
        let model = CalendarPresentationModel(mode: .detail)
        model.reconcile(
            year: 2026,
            availableMonths: (1 ... 10).map { month($0) },
            currentMonth: month(7),
            estimateMonth: month(7),
        )
        return model
    }

    @Test func pinchThresholdsAndRestoration() {
        let model = model()
        model.remember(.month(month(5)))
        model.finishPinch(magnification: 0.81, destination: nil)
        #expect(model.mode == .detail)
        model.finishPinch(magnification: 0.8, destination: nil)
        #expect(model.mode == .overview)
        model.finishPinch(magnification: 1.19, destination: .month(month(9)))
        #expect(model.mode == .overview)
        model.toggle()
        #expect(model.target == .month(month(5)))
        model.toggle()
        model.finishPinch(magnification: 1.2, destination: .month(month(9)))
        #expect(model.mode == .detail)
        #expect(model.target == .month(month(9)))
    }

    @Test func unavailableMonthRejectsButPlannedFutureMonthExpands() {
        let model = model()
        model.toggle()
        #expect(!model.expand(.month(month(11))))
        #expect(model.mode == .overview)
        #expect(model.rejectedTarget == .month(month(11)))
        #expect(model.rejectionCount == 1)
        model.finishPinch(magnification: 1.3, destination: .month(month(11)))
        #expect(model.rejectionCount == 2)
        #expect(model.expand(.month(month(10))))
        #expect(model.target == .month(month(10)))
    }

    @Test func estimateRestoresAndReconcilesWhenHidden() {
        let model = model()
        model.toggle()
        #expect(model.expand(.estimate(month(7))))
        #expect(model.target == .estimate(month(7)))
        model.reconcile(
            year: 2026,
            availableMonths: (1 ... 7).map { month($0) },
            currentMonth: month(7),
            estimateMonth: nil,
        )
        #expect(model.target == .month(month(7)))
        #expect(!model.isAvailable(.estimate(month(7))))
    }

    @Test func yearChangePreservesZoomAndUsesLastAvailableMonth() {
        let model = model()
        model.toggle()
        model.reconcile(
            year: 2025,
            availableMonths: (1 ... 12).map { month($0, year: 2025) },
            currentMonth: nil,
            estimateMonth: nil,
        )
        #expect(model.mode == .overview)
        #expect(model.target == .month(month(12, year: 2025)))
        model.reconcile(year: 2027, availableMonths: [], currentMonth: nil, estimateMonth: nil)
        #expect(model.target == nil)
        #expect(!model.expand(nil))
    }

    @Test func overviewAvailabilityMatchesDetailedPlanningVisibility() throws {
        let report = PreviewSupport.plannedStayYearReportModel()
        let yearReport = try #require(report.report)
        let months = try yearReport.calendarMonths(
            calendar: report.calendar,
            referenceDate: report.referenceDate,
            flightDays: [],
        )
        let visible = CalendarPresentationModel.visibleMonths(
            months,
            report: report,
            focusedRegion: nil,
        )
        #expect(months.count == 12)
        #expect(visible.contains { $0.month > 7 })
        let hidden = PreviewSupport.plannedStayYearReportModel(showsEstimatedTimeAndPlanning: false)
        let hiddenMonths = CalendarPresentationModel.visibleMonths(
            months,
            report: hidden,
            focusedRegion: nil,
        )
        #expect(hiddenMonths.map(\.month) == Array(1 ... 7))
    }
}
