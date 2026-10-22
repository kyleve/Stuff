import SFSafeSymbols
import SwiftUI
import WhereCore

/// Builds gallery rows below the page's reveal and focus scopes so those scopes
/// store only this small view, rather than the complete concrete row tree.
struct PlacesYearFeaturesContent: View {
    let report: YearReportModel

    var body: some View {
        FeatureGuidePanel(
            title: .settingsExplorePlacesLocationsTitle,
            detail: .settingsExplorePlacesLocationsDetail,
            symbol: .mapFill,
        ) {
            if let region = report.locationRegions.first {
                RegionSummaryCard(
                    regionDays: region,
                    variant: .compact,
                    yearLength: report.daysInSelectedYear,
                    year: report.selectedYear,
                )
            }
            if let content = report.elsewhere.content(for: report.selectedYear),
               let region = content.regions.first
            {
                RegionSummaryCard(
                    regionDays: RegionDays(region: region.region, days: region.days.count),
                    variant: .elsewhere,
                    year: report.selectedYear,
                    recordedPoints: content.cardLocations.pointsByRegion[region.region] ?? [],
                    showsRecordedPoints: report.showsRecordedLocationDots,
                    recordedPointsID: content.cardLocations.id,
                )
            }
        }
        .task(id: report.elsewhereInput) {
            if let input = report.elsewhereInput { await report.elsewhere.refresh(input) }
        }
        .featureMarketingRow(order: 1)
        .settingsRow(PlacesYearFeaturesView.Item.locations, restingBackground: .clear)
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
        FeatureGuidePanel(
            title: .settingsExplorePlacesTimelineTitle,
            detail: .settingsExplorePlacesTimelineDetail,
            symbol: .calendarDayTimelineLeft,
        ) {
            PresenceTimelineList(report: report, presentation: .excerpt)
        }
        .featureMarketingRow(order: 3)
        .settingsRow(PlacesYearFeaturesView.Item.timeline, restingBackground: .clear)
        FeatureGuidePanel(
            title: .settingsExplorePlacesWelcomeTitle,
            detail: .settingsExplorePlacesWelcomeDetail,
            symbol: .sparkles,
        ) {}
            .featureMarketingRow(order: 4)
            .settingsRow(PlacesYearFeaturesView.Item.welcome, restingBackground: .clear)
        FeatureSettingsLink(destination: .year).featureMarketingRow(order: 5)
        FeatureSettingsLink(destination: .appearance).featureMarketingRow(order: 6)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            PlacesYearFeaturesView(report: PreviewSupport.plannedStayYearReportModel(), focus: nil)
        }
        .whereBroadwayRoot()
    }
#endif
