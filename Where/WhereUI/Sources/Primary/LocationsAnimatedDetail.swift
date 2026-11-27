import SwiftUI

/// Animates mounted calendars so native scroll content moves in both directions.
struct LocationsAnimatedDetail: View {
    private struct Presentation {
        var current: LocationsView.CalendarSelection?
        var revealedID: LocationsView.CalendarSelection.ID?
        var calendars: [LocationsView.CalendarSelection]

        init(current: LocationsView.CalendarSelection?) {
            self.current = current
            revealedID = current?.id
            calendars = current.map { [$0] } ?? []
        }
    }

    let report: YearReportModel
    let navigation: LocationsView.Navigation
    let selection: LocationsView.CalendarSelection?
    @State private var presentation: Presentation
    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        navigation: LocationsView.Navigation,
        selection: LocationsView.CalendarSelection?,
    ) {
        self.report = report
        self.navigation = navigation
        self.selection = selection
        _presentation = State(initialValue: Presentation(current: selection))
    }

    var body: some View {
        let motion = stylesheet.locationsDetail
        ZStack {
            if presentation.current == nil {
                LocationsNoRegion(showsDescription: !report.locationRegions.isEmpty)
                    .transition(.opacity)
            }
            ForEach(presentation.calendars) { calendar in
                let isVisible = calendar.id == presentation.revealedID
                LocationsRegionCalendar(
                    report: report,
                    navigation: navigation,
                    selection: calendar,
                    showsEstimateCard: false,
                    showsZoomAction: isVisible,
                    onPresentationReady: { reveal(calendar.id) },
                )
                .scaleEffect(isVisible ? 1 : motion.calendarScale ?? 1)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
                .zIndex(calendar.id == presentation.current?.id ? 2 : 1)
                .transition(.identity)
            }
        }
        .onChange(of: selection?.id) { updateSelection() }
    }

    private func updateSelection() {
        let outgoing = presentation.current
        withAnimation(stylesheet.locationsDetail.animation, completionCriteria: .removed) {
            presentation.current = selection
            presentation.revealedID = nil
            if let selection {
                // A region can only have one calendar attached to its scroll position.
                presentation.calendars.removeAll { $0.region == selection.region }
                presentation.calendars.append(selection)
            }
        } completion: {
            guard let outgoing, presentation.current?.id != outgoing.id else { return }
            presentation.calendars.removeAll { $0.id == outgoing.id }
        }
    }

    private func reveal(_ id: LocationsView.CalendarSelection.ID) {
        guard presentation.current?.id == id, selection?.id == id,
              presentation.revealedID != id
        else { return }
        withAnimation(stylesheet.locationsDetail.animation) {
            presentation.revealedID = id
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        LocationsAnimatedDetail(
            report: report,
            navigation: LocationsView.Navigation(),
            selection: LocationsView.makeCalendarSelection(for: .california, report: report),
        )
        .whereBroadwayRoot()
    }
#endif
