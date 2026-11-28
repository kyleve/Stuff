import BroadwayUI
import RegionKit
import SwiftUI
import WhereCore

struct LocationRegionCardButton: View {
    let item: RegionDays
    let report: YearReportModel
    let tilt: TiltProvider
    let cardVariant: WhereStylesheet.CardStyle.Variant
    let showsSelection: Bool
    let navigation: LocationsView.Navigation
    let cardPresentation: LocationCardsPresentationModel
    let calendarTransition: Namespace.ID
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let isSelected = showsSelection && navigation.selectedRegion == item.region
        let tint = regionStyles.style(for: item.region).tint
        Button {
            if showsSelection {
                navigation.toggleSelection(of: item.region)
            } else {
                navigation.select(region: item.region)
            }
        } label: {
            RegionSummaryCard(
                regionDays: item,
                variant: cardVariant,
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
        .buttonStyle(stylesheet.card[cardVariant].buttonStyle(tint: tint))
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
            let card = stylesheet.card[cardVariant]
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
        .accessibilityHint(String(localized: isSelected
                ? .primaryCardClearSelectionHint : .primaryCardCalendarHint))
        .locationCardOvertakeEffect(
            region: item.region,
            presentation: cardPresentation,
            motion: stylesheet.locationCardStack.overtake,
        )
        .locationCardRankingRegion(item.region)
        .id(item.region)
        .presenceSelection(
            isSelected,
            tint: tint,
            cornerRadius: stylesheet.card[cardVariant].cornerRadius,
        )
    }

    private func estimatedDays(for region: Region) -> DayBounds? {
        guard report.showsEstimatedTimeAndPlanning else { return nil }
        return report.primaryRegionForecast(for: region)?.estimatedTotalDays
    }
}

#if DEBUG
    #Preview("Region card selection") {
        LocationsView(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
    }
#endif
