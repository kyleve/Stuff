import SFSafeSymbols
import SwiftUI
import WhereCore

/// The selected calendar and its empty state share the Locations toolbar.
struct LocationsDetailContent: View {
    let report: YearReportModel
    @Bindable var navigation: LocationsView.Navigation
    let calendarPresentation: CalendarPresentationState
    let showsEstimateCard: Bool

    var body: some View {
        Group {
            if let region = navigation.selectedRegion {
                CalendarContentView(
                    focusedRegion: region,
                    report: report,
                    showsEstimateCard: showsEstimateCard,
                    showsPlanningAction: false,
                    presentationState: calendarPresentation,
                    persistenceKey: .region(region),
                    scrollRole: LocationsView.ScrollRole.calendar,
                    planningDestination: $navigation.planningDestination,
                )
                .id(region)
            } else {
                ContentUnavailableView {
                    Label(String(localized: .locationsNoRegionTitle), systemSymbol: .calendar)
                } description: {
                    if !report.locationRegions.isEmpty {
                        Text(String(localized: .locationsNoRegionDescription))
                    }
                }
            }
        }
        .toolbar { LocationsToolbar(report: report, navigation: navigation) }
    }
}

#if DEBUG
    #Preview {
        let navigation = LocationsView.Navigation()
        let _ = navigation.select(region: .california)
        NavigationStack {
            LocationsDetailContent(
                report: PreviewSupport.loadedYearReportModel(),
                navigation: navigation,
                calendarPresentation: CalendarPresentationState(mode: .detail),
                showsEstimateCard: true,
            )
        }
        .whereBroadwayRoot()
    }
#endif
