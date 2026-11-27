import SFSafeSymbols
import SwiftUI
import WhereCore

/// Renders the same journey rows in the full timeline and in feature excerpts.
struct PresenceTimelineRows: View {
    enum Item: Hashable, Identifiable {
        case recorded(PresenceJourneyItem)
        case planned(PlanningTimelineItem)
        case estimate

        var id: PresenceTimelineList.RowID {
            switch self {
                case let .recorded(item): .init(item)
                case let .planned(item): .planned(item.id)
                case .estimate: .estimate
            }
        }

        static func ordered(
            recorded: [PresenceJourneyItem],
            planned: [PlanningTimelineItem],
            estimateDay: CalendarDay?,
            calendar: Calendar,
        ) -> [Self] {
            guard let estimateDay
            else { return recorded.map(Self.recorded) + planned.map(Self.planned) }

            let divider = recorded.firstIndex {
                CalendarDay(from: $0.start, in: calendar) > estimateDay
            } ?? recorded.endIndex
            let history = recorded[..<divider]
            var beforeEstimate = history.map(Self.recorded)
            var laterPlans = planned[...]
            if let plan = planned.first {
                let afterLastFlight = history.lastIndex {
                    if case .flight = $0 { return true }
                    return false
                }.map { $0 + 1 } ?? history.startIndex
                let plannedRow = Self.planned(plan)
                if let current = history[afterLastFlight...].lastIndex(where: {
                    plannedRow.continues(.recorded($0), calendar: calendar)
                }) {
                    // A shorter overlapping visit can appear after the current stay.
                    // Keep the current stay and the first planned segment together.
                    let currentRow = beforeEstimate.remove(at: current)
                    beforeEstimate.append(currentRow)
                    beforeEstimate.append(plannedRow)
                    laterPlans = laterPlans.dropFirst()
                }
            }
            return beforeEstimate + [.estimate] + recorded[divider...].map(Self.recorded)
                + laterPlans.map(Self.planned)
        }

        func continues(_ previous: Self?, calendar: Calendar) -> Bool {
            guard case let .planned(plan) = self,
                  case let .recorded(.stay(stint)) = previous
            else { return false }
            return plan.continues(stint, calendar: calendar)
        }
    }

    let items: [Item]
    let report: YearReportModel
    let forecasts: [LocationForecast]
    let openPlanning: ((PlannedStaysDestination) -> Void)?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ForEach(items.enumerated(), id: \.element.id) { index, item in
            let previous = index > items.startIndex ? items[index - 1] : nil
            let next = index + 1 < items.endIndex ? items[index + 1] : nil
            let calendar = report.calendar
            let isFirst = previous == nil || previous == .estimate
            let isLast = next == nil || next == .estimate
            Group {
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
                        .padding(.bottom, next == nil ? 0 : stylesheet.spacing.large)
                }
            }
            .fixedSize(horizontal: false, vertical: openPlanning == nil)
            .id(item.id)
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
                Button(
                    String(localized: .plannedStaysTitle),
                    systemSymbol: .calendarBadgeClock,
                    action: edit,
                )
            }
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
            .whereBroadwayRoot()
    }
#endif
