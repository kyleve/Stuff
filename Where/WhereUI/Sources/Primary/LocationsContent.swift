import PeriscopeCore
import SwiftUI
import WhereCore

/// Locations tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards, with the Elsewhere summary folded in
/// at the bottom (only when there are secondary regions), plus toolbar actions
/// for planned stays and any data issues that need resolution.
struct LocationsContent: View {
    let report: YearReportModel
    var openElsewhere: (() -> Void)?
    let cardVariant: WhereStylesheet.CardStyle.Variant
    let showsSelection: Bool
    let showsToolbarActions: Bool

    @State private var navigation: LocationsView.Navigation
    @State private var isCardSurfaceVisible = false
    @State private var cardPresentation: LocationCardsPresentationModel

    /// Drives the region cards' tilt-reactive light sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    /// Pairs a tapped card with its pushed calendar so the navigation uses a
    /// matched-geometry zoom (the card expands into the calendar) rather than a
    /// plain slide.
    @Namespace private var localCalendarTransition
    private let transition: Namespace.ID?
    private var calendarTransition: Namespace.ID {
        transition ?? localCalendarTransition
    }

    @Environment(\.stylesheet.card.regular.surface) private var cardSurface

    private var isCardSurfaceUncovered: Bool {
        isCardSurfaceVisible
            && navigation.flightReview == nil
            && !navigation.showingResolution
            && navigation.planningDestination == nil
    }

    init(
        report: YearReportModel,
        navigation: LocationsView.Navigation? = nil,
        cardPresentation: LocationCardsPresentationModel? = nil,
        tilt: TiltProvider? = nil,
        calendarTransition: Namespace.ID? = nil,
        cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        showsSelection: Bool = false,
        showsToolbarActions: Bool = true,
        openElsewhere: (() -> Void)? = nil,
    ) {
        _navigation = State(initialValue: navigation ?? LocationsView.Navigation())
        self.report = report
        self.openElsewhere = openElsewhere
        self.cardVariant = cardVariant
        self.showsSelection = showsSelection
        self.showsToolbarActions = showsToolbarActions
        transition = calendarTransition
        _tilt = State(initialValue: tilt ?? TiltProvider())
        _cardPresentation = State(initialValue: cardPresentation ?? LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        LocationsScreen(
            report: report,
            navigation: navigation,
            cardPresentation: cardPresentation,
            tilt: tilt,
            calendarTransition: calendarTransition,
            cardVariant: cardVariant,
            showsSelection: showsSelection,
            isCardSurfaceUncovered: isCardSurfaceUncovered,
            isCardSurfaceVisible: $isCardSurfaceVisible,
            openPlanning: openPlanning,
            openElsewhere: openElsewhere,
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsToolbarActions {
                LocationsToolbar(report: report, navigation: navigation)
            }
        }
        .observesTilt(tilt, enabled: isCardSurfaceUncovered && cardSurface.usesReflection)
        .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
    }

    private func openPlanning() {
        navigation.planningDestination = .list
    }
}

#if DEBUG
    #Preview("Locations") {
        LocationsView(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
    }
#endif
