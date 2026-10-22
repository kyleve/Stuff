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
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let presentedCards = cardPresentation.presented(report.locationRegions)

        // Keep the flight notice immediately below navigation. Without a notice,
        // a short card list retains its centered presentation.
        return ScrollView {
            VStack(spacing: stylesheet.spacing.xxLarge) {
                LocationsFlightNotice(report: report)

                LocationCardRankingStack(
                    spacing: stylesheet.spacing.xxLarge,
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
                            )
                        }
                        .buttonStyle(stylesheet.card.regular.buttonStyle(
                            tint: regionStyles.style(for: item.region).tint,
                        ))
                        // The card is the zoom source: tapping it expands the
                        // card into the pushed calendar (matched geometry). The
                        // configuration re-states the card's rounded shape and
                        // its glow/lift shadows so the transition interpolates
                        // them — without it, the zoom clips the source to a bare
                        // rectangle and the card's soft shadow pops on/off.
                        .matchedTransitionSource(
                            id: item.region,
                            in: calendarTransition,
                        ) { source in
                            let card = stylesheet.card.regular
                            let tint = regionStyles.style(for: item.region).tint
                            let elevation = card.transitionElevation(tint: tint)
                            return source
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: card.cornerRadius,
                                        style: .continuous,
                                    ),
                                )
                                .shadow(
                                    color: elevation.glow.color,
                                    radius: elevation.glow.radius,
                                )
                                .shadow(
                                    color: elevation.lift.color,
                                    radius: elevation.lift.radius,
                                    y: elevation.lift.offsetY,
                                )
                        }
                        .accessibilityHint(String(localized: .primaryCardCalendarHint))
                        .locationCardOvertakeEffect(
                            region: item.region,
                            presentation: cardPresentation,
                            motion: stylesheet.locationCardStack.overtake,
                        )
                        .locationCardRankingRegion(item.region)
                    }
                }

                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top)
        .scrollBounceBehavior(.basedOnSize)
        // The card normally stays clipped to the scrolling viewport. Reveal
        // overflow only while the authored arc, scale, and rotation need it.
        .scrollClipDisabled(cardPresentation.isSpatialOvertakeActive)
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
        CalendarContentView(focusedRegion: region, report: report)
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
