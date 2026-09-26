import SwiftUI
import WhereCore

/// A bounded excerpt of production journey rows. It never opens the plan editor.
struct FeatureTimelinePreview: View {
    let report: YearReportModel

    var body: some View {
        if let loaded = report.report {
            let stints = Array(PresenceTimeline.stints(from: loaded, calendar: report.calendar)
                .suffix(2))
            let plannedInterval = report.showsEstimatedTimeAndPlanning
                ? report.forecasts.plannedInterval(intersecting: report.selectedYear)
                : nil
            let joinsPlannedStay = if let plannedInterval, let currentStint = stints.last {
                plannedInterval.region == currentStint.region
                    && CalendarDay(from: currentStint.end, in: report.calendar).adding(days: 1)
                    == plannedInterval.start
            } else {
                false
            }

            VStack(spacing: 0) {
                ForEach(stints) { stint in
                    PresenceJourneyRow(
                        stint: stint,
                        calendar: report.calendar,
                        daysInYear: report.daysInSelectedYear,
                        isFirst: stint.id == stints.first?.id,
                        isLast: plannedInterval == nil && stint.id == stints.last?.id,
                        cardPosition: joinsPlannedStay && stint.id == stints.last?.id
                            ? .top : .standalone,
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let plannedInterval {
                    PlannedPresenceJourneyRow(
                        interval: plannedInterval,
                        calendar: report.calendar,
                        daysInYear: report.daysInSelectedYear,
                        isFirst: stints.isEmpty,
                        cardPosition: joinsPlannedStay ? .bottom : .standalone,
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                if stints.isEmpty, plannedInterval == nil {
                    Text(.settingsExploreHistoryEmpty).font(.subheadline)
                }
            }
        } else {
            Text(.settingsExploreHistoryUnavailable).font(.subheadline)
        }
    }
}

#if DEBUG
    #Preview {
        FeatureTimelinePreview(report: PreviewSupport.plannedStayYearReportModel())
            .whereBroadwayRoot()
    }
#endif
