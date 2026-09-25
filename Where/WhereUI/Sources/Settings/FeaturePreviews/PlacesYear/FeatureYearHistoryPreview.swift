import SwiftUI

/// The production year ribbon, without loading or changing a report.
struct FeatureYearHistoryPreview: View {
    let report: YearReportModel

    var body: some View {
        if let loaded = report.report {
            YearRibbon(days: loaded.days, year: report.selectedYear, calendar: report.calendar)
            if loaded.days.isEmpty { Text(.settingsExploreHistoryEmpty).font(.subheadline) }
        } else {
            Text(.settingsExploreHistoryUnavailable).font(.subheadline)
        }
    }
}

#if DEBUG
    #Preview {
        FeatureYearHistoryPreview(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
    }
#endif
