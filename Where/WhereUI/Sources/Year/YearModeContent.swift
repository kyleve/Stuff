import SwiftUI
import WhereCore

/// The single report-state gate for every Your Year lens. Calendar keeps its
/// own gate because it is also hosted outside `YearView`.
struct YearModeContent: View {
    let report: YearReportModel
    let mode: YearViewMode

    var body: some View {
        Group {
            if let yearReport = report.report {
                let overview = YearOverview(
                    report: yearReport,
                    referenceDate: report.referenceDate,
                    calendar: report.calendar,
                )
                switch mode {
                    case .calendar:
                        CalendarContentView(report: report)
                            .transition(.opacity)
                    case .timeline:
                        PresenceTimelineList(report: report)
                            .transition(.opacity)
                    case .breakdown:
                        YearBreakdownView(overview: overview)
                            .transition(.opacity)
                    case .heatmap:
                        YearHeatmapView(overview: overview, calendar: report.calendar)
                            .transition(.opacity)
                }
            } else if case let .failed(error) = report.loadState {
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemImage: "exclamationmark.icloud",
                    )
                } description: {
                    Text(error.message)
                }
            } else {
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            }
        }
    }
}

#if DEBUG
    #Preview {
        YearModeContent(
            report: PreviewSupport.loadedYearReportModel(),
            mode: .breakdown,
        )
        .whereBroadwayRoot()
    }
#endif
