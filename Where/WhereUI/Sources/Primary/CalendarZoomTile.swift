import RegionKit
import SwiftUI
import WhereCore

struct CalendarZoomTile: View {
    let target: CalendarPresentationState.Target
    let mode: CalendarPresentationState.Mode
    let months: [CalendarMonth]
    let report: YearReportModel
    let focusedRegion: Region?
    let presentation: CalendarPresentationState
    let forecasts: [LocationForecast]
    let onPlan: () -> Void

    var body: some View {
        switch target {
            case let .month(day):
                if let month = months.first(where: { $0.firstCalendarDay == day }) {
                    MonthGridView(
                        month: month,
                        focusedRegion: focusedRegion,
                        report: report,
                        compact: mode == .overview,
                        isAvailable: presentation.isAvailable(target),
                    )
                }
            case .estimate:
                LocationForecastPanel(
                    forecasts: forecasts,
                    microprintRegions: report.ranking.primary.map(\.region),
                    homeRegion: report.forecasts.planning.homeRegion,
                    planningAction: mode == .detail ? onPlan :
                        nil,
                )
        }
    }
}

#if DEBUG
    #Preview("Month tile") {
        let report = PreviewSupport.plannedStayYearReportModel()
        let month = PreviewSupport.calendarAccessibilityMonth(calendar: report.calendar)
        let presentation = CalendarPresentationState(mode: .detail)
        CalendarZoomTile(
            target: .month(month.firstCalendarDay),
            mode: .detail,
            months: [month],
            report: report,
            focusedRegion: nil,
            presentation: presentation,
            forecasts: report.primaryRegionForecasts,
            onPlan: {},
        )
        .whereBroadwayRoot()
    }
#endif
