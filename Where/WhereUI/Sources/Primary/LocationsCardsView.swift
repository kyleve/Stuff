import BroadwayUI
import RegionKit
import SwiftUI
import WhereCore

/// Ranked cards have their own body so the navigation shell does not copy the
/// full card composition while constructing loading and failure states.
struct LocationsCardsView: View {
    let report: YearReportModel
    let cardPresentation: LocationCardsPresentationModel
    let tilt: TiltProvider
    let calendarTransition: Namespace.ID
    let isCardSurfaceUncovered: Bool
    @Binding var isCardSurfaceVisible: Bool
    let planningAction: () -> Void
    @Bindable var navigation: LocationsView.Navigation
    let cardVariant: WhereStylesheet.CardStyle.Variant
    let showsSelection: Bool

    @BScrollPosition<Region, Int> private var position: ScrollPosition
    enum ScrollRole: Hashable {
        case browse
    }

    init(
        report: YearReportModel,
        cardPresentation: LocationCardsPresentationModel,
        tilt: TiltProvider,
        calendarTransition: Namespace.ID,
        isCardSurfaceUncovered: Bool,
        isCardSurfaceVisible: Binding<Bool>,
        planningAction: @escaping () -> Void,
        navigation: LocationsView.Navigation,
        cardVariant: WhereStylesheet.CardStyle.Variant,
        showsSelection: Bool,
    ) {
        self.report = report
        self.cardPresentation = cardPresentation
        self.tilt = tilt
        self.calendarTransition = calendarTransition
        self.isCardSurfaceUncovered = isCardSurfaceUncovered
        _isCardSurfaceVisible = isCardSurfaceVisible
        self.planningAction = planningAction
        self.navigation = navigation
        self.cardVariant = cardVariant
        self.showsSelection = showsSelection
        _position = BScrollPosition(
            Self.self,
            role: ScrollRole.browse,
            context: { report.selectedYear },
            idType: Region.self,
        )
    }

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let presentedCards = cardPresentation.presented(report.locationRegions)

        // Keep the flight notice immediately below navigation. Without a notice,
        // a short card list retains its centered presentation.
        return ScrollView {
            VStack(spacing: stylesheet.spacing.xxLarge) {
                LocationsFlightNotice(report: report, openReview: { navigation.flightReview = $0 })

                LocationCardRankingStack(
                    spacing: stylesheet.spacing.xxLarge,
                    presentation: cardPresentation,
                    motion: stylesheet.locationCardStack.overtake,
                ) {
                    ForEach(presentedCards) { item in
                        LocationRegionCardButton(
                            item: item,
                            report: report,
                            tilt: tilt,
                            cardVariant: cardVariant,
                            showsSelection: showsSelection,
                            navigation: navigation,
                            cardPresentation: cardPresentation,
                            calendarTransition: calendarTransition,
                        )
                    }
                }

                .scrollTargetLayout()

                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding()
            .whereContentRoot()
        }
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top, for: .alignment)
        .scrollPosition($position)
        .onChange(of: report.selectedYear, initial: true) {
            _position.initialize(edge: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Let card shadows extend past the browse column. Compact cards only
        // need overflow during an overtake.
        .scrollClipDisabled(cardVariant == .column || cardPresentation.isSpatialOvertakeActive)
        .accessibilityIdentifier("where_root_title")
        .onAppear { isCardSurfaceVisible = true }
        .onDisappear { isCardSurfaceVisible = false }
        // Count, order, flourish, persistence, and haptic all share this one
        // visibility-aware delayed reconciliation.
        .reconcilesLocationCards(
            current: report.locationRegions,
            year: report.selectedYear,
            isVisible: isCardSurfaceUncovered,
            presentation: cardPresentation,
            motion: stylesheet.locationCardStack.overtake,
        )
    }
}

#if DEBUG
    #Preview {
        LocationsView(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
    }
#endif
