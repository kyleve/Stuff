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

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.whereComponentStylesheet) private var componentStylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var artworkSpacing: CGFloat {
        let bounds = componentStylesheet[.regularCard].outsets
        return stylesheet.spacing.xxLarge + bounds.top + bounds.bottom
    }

    private var additionalGutter: CGFloat {
        let bounds = componentStylesheet[.regularCard].outsets
        return max(0, max(bounds.leading, bounds.trailing) - stylesheet.spacing.xxLarge)
    }

    var body: some View {
        let presentedCards = cardPresentation.presented(report.locationRegions)

        // Keep the flight notice immediately below navigation. Without a notice,
        // a short card list retains its centered presentation.
        return ScrollView {
            VStack(spacing: stylesheet.spacing.xxLarge) {
                LocationsFlightNotice(report: report)

                LocationCardRankingStack(
                    spacing: artworkSpacing,
                    presentation: cardPresentation,
                    motion: stylesheet.locationCardStack.overtake,
                ) {
                    ForEach(presentedCards) { item in
                        NavigationLink {
                            calendarDestination(item.region)
                        } label: {
                            RegionSummaryCard(
                                regionDays: item,
                                interactive: true,
                                yearLength: report.daysInSelectedYear,
                                estimatedDays: estimatedDays(for: item.region),
                                year: report.selectedYear,
                                tilt: tilt,
                                recordedPoints: report.primaryRegionLocations?
                                    .pointsByRegion[item.region] ?? [],
                                showsRecordedPoints: report.showsRecordedLocationDots,
                                recordedPointsID: report.primaryRegionLocations?.id,
                                transitionNamespace: calendarTransition,
                            )
                        }
                        .buttonStyle(stylesheet.card.regular.buttonStyle(
                            tint: regionStyles.style(for: item.region).tint,
                        ))
                        .accessibilityHint(String(localized: .primaryCardCalendarHint))
                        .locationCardOvertakeEffect(
                            region: item.region,
                            presentation: cardPresentation,
                            motion: stylesheet.locationCardStack.overtake,
                        )
                        .locationCardRankingRegion(item.region)
                    }
                }

                .padding(.top, componentStylesheet[.regularCard].outsets.top)
                .padding(.bottom, componentStylesheet[.regularCard].outsets.bottom)

                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding(stylesheet.spacing.xxLarge)
            .padding(.horizontal, additionalGutter)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top)
        .scrollBounceBehavior(.basedOnSize)
        // Theme artwork remains clipped to the scrolling viewport during ranking changes.
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

    private func estimatedDays(for region: Region) -> DayBounds? {
        guard report.showsEstimatedTimeAndPlanning else { return nil }
        return report.forecasts.forecast(for: region, report: report.report)?.estimatedTotalDays
    }

    /// The region's calendar, pushed as a nested view. It's the zoom
    /// destination: the tapped card expands into it via matched geometry, and the
    /// stack's back gesture collapses it again.
    private func calendarDestination(_ region: Region) -> some View {
        CalendarContentView(focusedRegion: region, report: report, persistenceKey: .region(region))
            .navigationTitle(
                WhereFormat.calendarRegionTitle(region: region, year: report.selectedYear),
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTransition(.zoom(sourceID: region, in: calendarTransition))
    }
}

#if DEBUG
    #Preview {
        LocationsView(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
    }
#endif
