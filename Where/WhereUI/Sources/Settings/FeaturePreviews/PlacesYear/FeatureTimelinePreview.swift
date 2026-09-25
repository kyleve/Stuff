import SwiftUI

/// A bounded excerpt of production journey rows. It never opens the plan editor.
struct FeatureTimelinePreview: View {
    let report: YearReportModel

    var body: some View {
        if let loaded = report.report {
            let stints = Array(PresenceTimeline.stints(from: loaded, calendar: report.calendar)
                .suffix(2))
            ForEach(stints) { stint in
                PresenceJourneyRow(
                    stint: stint,
                    calendar: report.calendar,
                    daysInYear: report.daysInSelectedYear,
                    isFirst: stint.id == stints.first?.id,
                    isLast: stint.id == stints.last?.id,
                    cardPosition: .standalone,
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if report.showsEstimatedTimeAndPlanning,
               let interval = report.forecasts.plannedInterval(intersecting: report.selectedYear)
            {
                PlannedPresenceJourneyRow(
                    interval: interval,
                    calendar: report.calendar,
                    daysInYear: report.daysInSelectedYear,
                    isFirst: stints.isEmpty,
                    cardPosition: .standalone,
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if stints.isEmpty { Text(.settingsExploreHistoryEmpty).font(.subheadline) }
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
