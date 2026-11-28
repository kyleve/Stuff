import SwiftUI

/// Animates region changes in the side-by-side Locations detail pane.
///
/// When switching regions, `current` updates immediately. The outgoing calendar stays
/// mounted for its exit animation, while the incoming calendar mounts with zero opacity.
/// Once its content has laid out, `reveal(_:)` sets `revealedID` and animates it into view.
/// Reveal and removal use each opening's ID because the user can reopen the same region
/// before its previous exit animation finishes.
struct LocationDetailPaneContainer: View {
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
    @Environment(LocationsView.CalendarPresentations.self) private var calendars

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
        let currentID = presentation.current?.id
        let revealedID = presentation.revealedID
        ZStack {
            if currentID == nil {
                LocationsNoRegion(showsDescription: !report.locationRegions.isEmpty)
                    .transition(.opacity)
            }
            ForEach(presentation.calendars) { calendar in
                let isVisible = calendar.id == revealedID
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
                .zIndex(calendar.id == currentID ? 2 : 1)
                .transition(.identity)
            }
        }
        .onAppear { calendars.retain(presentation.calendars) }
        .onChange(of: selection?.id) { updateSelection() }
        .onDisappear {
            for calendar in presentation.calendars where calendar.id != presentation.current?.id {
                calendars.discard(calendar)
            }
        }
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
            calendars.retain(presentation.calendars)
        } completion: {
            guard let outgoing, presentation.current?.id != outgoing.id else { return }
            presentation.calendars.removeAll { $0.id == outgoing.id }
            calendars.discard(outgoing)
        }
    }

    private func reveal(_ id: LocationsView.CalendarSelection.ID) {
        guard presentation.current?.id == id, calendars.selected?.id == id,
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
        let calendars = LocationsView.makeCalendarPresentations(for: .california, report: report)
        LocationDetailPaneContainer(
            report: report,
            navigation: LocationsView.Navigation(),
            selection: calendars.selected,
        )
        .environment(calendars)
        .whereBroadwayRoot()
    }
#endif
