import SwiftUI

/// Shares the estimate panel across ranked, empty, and Elsewhere-only states.
struct LocationsEstimatePanel: View {
    let report: YearReportModel
    let planningAction: () -> Void

    var body: some View {
        let forecasts = report.forecasts.leadingForecasts(report: report.report)
        if report.showsEstimatedTimeAndPlanning, !forecasts.isEmpty {
            LocationForecastPanel(
                forecasts: forecasts,
                microprintRegions: report.ranking.primary.map(\.region).filter { $0 != .other },
                homeRegion: report.forecasts.planning.homeRegion,
                planningAction: planningAction,
                presentation: .collapsible,
            )
        }
    }
}

#if DEBUG
    #Preview {
        LocationsEstimatePanel(
            report: PreviewSupport.itineraryYearReportModel(),
            planningAction: {},
        )
        .whereBroadwayRoot()
    }
#endif
