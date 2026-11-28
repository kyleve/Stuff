import SFSafeSymbols
import SwiftUI
import WhereCore

struct PresenceTimelineItemRow: View {
    let item: PresenceTimelineRows.Item
    let previous: PresenceTimelineRows.Item?
    let next: PresenceTimelineRows.Item?
    let report: YearReportModel
    let forecasts: [LocationForecast]
    let openPlanning: ((PlannedStaysDestination) -> Void)?
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let calendar = report.calendar
        let isFirst = previous == nil || previous == .estimate
        let isLast = next == nil || next == .estimate
        switch item {
            case let .recorded(.stay(stint)):
                PresenceJourneyRow(
                    stint: stint,
                    calendar: calendar,
                    daysInYear: report.daysInSelectedYear,
                    isFirst: isFirst,
                    isLast: isLast,
                    cardPosition: next?.continues(item, calendar: calendar) == true
                        ? .top : .standalone,
                )
            case let .recorded(.flight(flight)):
                FlightJourneyRow(
                    flight: flight,
                    calendar: calendar,
                    isFirst: isFirst,
                    isLast: isLast,
                )
            case let .planned(plan):
                let row = PlannedPresenceJourneyRow(
                    item: plan,
                    calendar: calendar,
                    daysInYear: report.daysInSelectedYear,
                    isFirst: isFirst,
                    isLast: isLast,
                    cardPosition: item.continues(previous, calendar: calendar)
                        ? .bottom : .standalone,
                )
                if let openPlanning {
                    EditableTimelinePlan(row: row) { edit(plan, openPlanning: openPlanning)
                    }
                } else {
                    row
                }
            case .estimate:
                LocationForecastPanel(
                    forecasts: forecasts,
                    microprintRegions: report.ranking.primary.map(\.region),
                    homeRegion: report.forecasts.planning.homeRegion,
                    planningAction: openPlanning.map { action in { action(.list) } },
                )
                .padding(.top, previous == nil ? 0 : stylesheet.spacing.large)
                // Include the final inset in the estimate's bottom-aligned scroll target.
                .padding(.bottom, stylesheet.spacing.large)
        }
    }

    private func edit(
        _ item: PlanningTimelineItem,
        openPlanning: (PlannedStaysDestination) -> Void,
    ) {
        if case let .stay(interval) = item,
           let stay = report.forecasts.planning.stays.first(where: { $0.id == interval.stayID })
        {
            openPlanning(.edit(stay))
        } else {
            openPlanning(.list)
        }
    }
}

private struct EditableTimelinePlan: View {
    let row: PlannedPresenceJourneyRow
    let edit: () -> Void

    var body: some View {
        Button(action: edit) { row }
            .buttonStyle(.plain)
            .contextMenu {
                TimelinePlanningButton(action: edit)
            }
    }
}

/// A completed flight on the same connected rail as recorded and planned stays.
struct FlightJourneyRow: View {
    let flight: FlightAssessment
    let calendar: Calendar
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        if case let .completed(arrival) = flight.progress {
            HStack(spacing: stylesheet.timeline.rail.toCardSpacing) {
                Color.clear.frame(width: stylesheet.timeline.rail.nodeSize)

                FlightJourneyDetails(flight: flight, arrival: arrival, calendar: calendar)
            }
            .padding(.vertical, stylesheet.timeline.flight.verticalPadding)
            .background(alignment: .leading) {
                PresenceJourneyRail(
                    tint: stylesheet.timeline.flight.tint,
                    marker: .flight,
                    isFirst: isFirst,
                    isLast: isLast,
                )
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineList(report: PreviewSupport.flightYearReportModel(state: .completed))
            .whereBroadwayRoot()
    }
#endif
