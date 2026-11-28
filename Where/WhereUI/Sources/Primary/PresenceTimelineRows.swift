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
            var beforeEstimate = recorded[..<divider].map(Self.recorded)
            var laterPlans = planned.map(Self.planned)[...]
            if let firstPlan = laterPlans.first,
               firstPlan.continues(beforeEstimate.last, calendar: calendar)
            {
                beforeEstimate.append(laterPlans.removeFirst())
            }
            return beforeEstimate + [.estimate] + recorded[divider...].map(Self.recorded)
                + laterPlans
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

    var body: some View {
        ForEach(items.enumerated(), id: \.element.id) { index, item in
            let previous = index > items.startIndex ? items[index - 1] : nil
            let next = index + 1 < items.endIndex ? items[index + 1] : nil

            PresenceTimelineItemRow(
                item: item,
                previous: previous,
                next: next,
                report: report,
                forecasts: forecasts,
                openPlanning: openPlanning,
            )

            .fixedSize(horizontal: false, vertical: openPlanning == nil)
            .id(item.id)
        }
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
            .whereBroadwayRoot()
    }
#endif
