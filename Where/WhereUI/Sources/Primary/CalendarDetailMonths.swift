import RegionKit
import SwiftUI
import WhereCore

struct CalendarDetailMonths: View {
    let months: [CalendarMonth]
    let estimateMonth: CalendarMonth?
    let report: YearReportModel
    let focusedRegion: Region?
    let forecasts: [LocationForecast]
    let focusedTarget: AccessibilityFocusState<CalendarPresentationState.Target?>.Binding
    let onPlan: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.calendar.monthSpacing) {
            ForEach(months) { month in
                let target = CalendarPresentationState.Target.month(month.firstCalendarDay)
                CalendarDetailMonthTile(
                    month: month,
                    report: report,
                    focusedRegion: focusedRegion,
                    target: target,
                )
                .id(target)
                .accessibilityFocused(focusedTarget, equals: target)
                if month.id == estimateMonth?.id {
                    let target = CalendarPresentationState.Target.estimate(month.firstCalendarDay)
                    CalendarDetailEstimateTile(
                        forecasts: forecasts,
                        report: report,
                        onPlan: onPlan,
                        target: target,
                    )
                    .id(target)
                    .accessibilityFocused(focusedTarget, equals: target)
                }
            }
        }
        .scrollTargetLayout()
    }
}

private struct CalendarDetailMonthTile: View {
    let month: CalendarMonth
    let report: YearReportModel
    let focusedRegion: Region?
    let target: CalendarPresentationState.Target

    var body: some View {
        MonthGridView(month: month, focusedRegion: focusedRegion, report: report)
            .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
                [.detail: [.tile(target): $0]]
            }
    }
}

private struct CalendarDetailEstimateTile: View {
    let forecasts: [LocationForecast]
    let report: YearReportModel
    let onPlan: () -> Void
    let target: CalendarPresentationState.Target

    var body: some View {
        LocationForecastPanel(
            forecasts: forecasts,
            microprintRegions: report.ranking.primary.map(\.region),
            homeRegion: report.forecasts.planning.homeRegion,
            planningAction: onPlan,
        )
        .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
            [.detail: [.tile(target): $0]]
        }
    }
}

#if DEBUG
    #Preview("Months and estimate") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .detail,
            )
        }
        .whereBroadwayRoot()
    }
#endif
