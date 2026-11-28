import RegionKit
import SwiftUI
import WhereCore

struct CalendarOverviewGrid: View {
    let months: [CalendarMonth]
    let availableMonths: [CalendarMonth]
    let estimateMonth: CalendarMonth?
    let report: YearReportModel
    let focusedRegion: Region?
    let forecasts: [LocationForecast]
    let presentation: CalendarPresentationState
    let onExpand: (CalendarPresentationState.Target) -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.calendar.monthSpacing) {
            LazyVGrid(
                columns: Array(repeating: GridItem(
                    .flexible(),
                    spacing: stylesheet.calendar.overview.spacing,
                ), count: stylesheet.calendar.overview.columns),
                spacing: stylesheet.calendar.overview.spacing,
            ) {
                ForEach(months) { month in
                    CalendarOverviewMonthButton(
                        month: month,
                        available: availableMonths.contains { $0.id == month.id },
                        report: report,
                        focusedRegion: focusedRegion,
                        presentation: presentation,
                        onExpand: onExpand,
                    )
                }
            }
            if let estimateMonth {
                CalendarOverviewEstimateButton(
                    month: estimateMonth,
                    report: report,
                    forecasts: forecasts,
                    onExpand: onExpand,
                )
            }
        }
    }
}

private struct CalendarOverviewEstimateButton: View {
    let month: CalendarMonth
    let report: YearReportModel
    let forecasts: [LocationForecast]
    let onExpand: (CalendarPresentationState.Target) -> Void

    var body: some View {
        let destination = CalendarPresentationState.Target.estimate(month.firstCalendarDay)
        Button { onExpand(destination) } label: {
            LocationForecastPanel(
                forecasts: forecasts,
                microprintRegions: report.ranking.primary.map(\.region),
                homeRegion: report.forecasts.planning.homeRegion,
            )
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
            [.overview: [.tile(destination): $0]]
        }
        .accessibilityHint(String(localized: .calendarExpandEstimate))
    }
}

#if DEBUG
    #Preview("Year overview") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
