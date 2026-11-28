import SFSafeSymbols
import SwiftUI
import WhereCore

struct PlacesCalendarGuideRow: View {
    let report: YearReportModel

    var body: some View {
        FeatureGuidePanel(
            title: .settingsExplorePlacesCalendarTitle,
            detail: .settingsExplorePlacesCalendarDetail,
            symbol: .calendar,
        ) {
            if let loaded = report.report {
                YearRibbon(
                    days: loaded.days,
                    year: report.selectedYear,
                    calendar: report.calendar,
                )
                if loaded.days.isEmpty {
                    Text(.settingsExploreHistoryEmpty).font(.subheadline)
                }
            } else {
                Text(.settingsExploreHistoryUnavailable).font(.subheadline)
            }
        }
        .featureMarketingRow(order: 2)
        .settingsRow(PlacesYearFeaturesView.Item.calendar, restingBackground: .clear)
    }
}

#if DEBUG
    #Preview { NavigationStack { PlacesYearFeaturesView(
        report: PreviewSupport.plannedStayYearReportModel(),
        focus: nil,
    ) }.whereBroadwayRoot() }
#endif
