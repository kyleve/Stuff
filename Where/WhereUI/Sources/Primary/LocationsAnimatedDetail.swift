import SwiftUI

/// Keeps each outgoing scroll view mounted until it finishes shrinking out.
struct LocationsAnimatedDetail: View {
    private struct Presentation {
        var current: LocationsView.CalendarSelection?
        var calendars: [LocationsView.CalendarSelection]

        init(current: LocationsView.CalendarSelection?) {
            self.current = current
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
                let isCurrent = calendar.id == presentation.current?.id
                LocationsRegionCalendar(
                    report: report,
                    navigation: navigation,
                    selection: calendar,
                    showsEstimateCard: false,
                    showsZoomAction: isCurrent,
                )
                .scaleEffect(isCurrent ? 1 : motion.calendarScale ?? 1)
                .opacity(isCurrent ? 1 : 0)
                .allowsHitTesting(isCurrent)
                .accessibilityHidden(!isCurrent)
                .zIndex(isCurrent ? 2 : 1)
                .transition(.asymmetric(insertion: motion.calendarTransition, removal: .identity))
            }
        }
        .onChange(of: selection?.id) { updateSelection() }
    }

    private func updateSelection() {
        let outgoing = presentation.current
        withAnimation(stylesheet.locationsDetail.animation, completionCriteria: .removed) {
            presentation.current = selection
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
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        LocationsAnimatedDetail(
            report: report,
            navigation: LocationsView.Navigation(),
            selection: LocationsView.CalendarSelection(region: .california, report: report),
        )
        .whereBroadwayRoot()
    }
#endif
