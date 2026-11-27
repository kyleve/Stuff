import SFSafeSymbols
import SwiftUI
import WhereCore

/// The selected calendar and its empty state share the Locations toolbar.
struct LocationsDetailContent: View {
    let report: YearReportModel
    let navigation: LocationsView.Navigation
    let selection: LocationsView.CalendarSelection?
    let arrangement: AdaptivePaneArrangement

    var body: some View {
        Group {
            if arrangement == .columns {
                LocationsAnimatedDetail(
                    report: report,
                    navigation: navigation,
                    selection: selection,
                )
            } else if let selection {
                LocationsRegionCalendar(
                    report: report,
                    navigation: navigation,
                    selection: selection,
                    showsEstimateCard: true,
                )
                .id(selection.id)
            } else {
                LocationsNoRegion(showsDescription: !report.locationRegions.isEmpty)
            }
        }
        .toolbar { LocationsToolbar(report: report, navigation: navigation) }
    }
}

struct LocationsRegionCalendar: View {
    let report: YearReportModel
    @Bindable var navigation: LocationsView.Navigation
    let selection: LocationsView.CalendarSelection
    let showsEstimateCard: Bool
    var showsZoomAction = true
    var onPresentationReady: (() -> Void)?

    var body: some View {
        CalendarContentView(
            focusedRegion: selection.region,
            report: report,
            showsEstimateCard: showsEstimateCard,
            showsPlanningAction: false,
            showsZoomAction: showsZoomAction,
            presentationState: selection.presentation,
            persistenceKey: .region(selection.region),
            scrollRole: LocationsView.ScrollRole.calendar,
            planningDestination: $navigation.planningDestination,
            onPresentationReady: onPresentationReady,
        )
    }
}

struct LocationsNoRegion: View {
    let showsDescription: Bool

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .locationsNoRegionTitle), systemSymbol: .calendar)
        } description: {
            if showsDescription {
                Text(String(localized: .locationsNoRegionDescription))
            }
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        let navigation = LocationsView.Navigation()
        let _ = navigation.select(region: .california)
        NavigationStack {
            LocationsDetailContent(
                report: report,
                navigation: navigation,
                selection: LocationsView.CalendarSelection(region: .california, report: report),
                arrangement: .compact,
            )
        }
        .whereBroadwayRoot()
    }
#endif
