import BroadwayUI
import RegionKit
import SwiftUI

struct LocationsCompactNavigation: View {
    let browse: LocationsBrowsePane
    let detail: LocationsDetailContent
    let report: YearReportModel
    @Bindable var navigation: LocationsView.Navigation
    let title: String
    let calendarTransition: Namespace.ID

    var body: some View {
        NavigationSplitView(
            columnVisibility: .constant(.all),
            preferredCompactColumn: $navigation.compactColumn,
        ) {
            browse
                .containerBackground(.clear, for: .navigation)
                .containerBackground(.clear, for: .navigationSplitView)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            LocationsCompactDetail(
                detail: detail,
                report: report,
                region: navigation.selectedRegion,
                title: title,
                calendarTransition: calendarTransition,
            )
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.horizontalSizeClass, .compact)
        .bHorizontalSizeClass(.compact)
    }
}

private struct LocationsCompactDetail: View {
    let detail: LocationsDetailContent
    let report: YearReportModel
    let region: Region?
    let title: String
    let calendarTransition: Namespace.ID

    var body: some View {
        NavigationStack {
            detail
                // The compact zoom carries this paper over the outgoing region cards.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .visitedRegionsBackground(report)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .containerBackground(.clear, for: .navigation)
        }
        .modifier(RegionCalendarTransition(
            region: region,
            namespace: calendarTransition,
        ))
        .containerBackground(.clear, for: .navigation)
    }
}

/// The compact calendar push zooms from its region card.
private struct RegionCalendarTransition: ViewModifier {
    let region: Region?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if let region {
            content.navigationTransition(.zoom(sourceID: region, in: namespace))
        } else {
            content
        }
    }
}

#if DEBUG
    #Preview("Compact calendar") {
        LocationsView(report: PreviewSupport.loadedYearReportModel(), initialRegion: .california)
            .whereBroadwayRoot()
    }
#endif
