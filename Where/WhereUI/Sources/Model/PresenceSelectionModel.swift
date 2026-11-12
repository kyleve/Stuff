import Foundation
import Observation
import RegionKit
import WhereCore

/// Connects explicit selections to displayed history data. It owns no scroll or presentation state.
@MainActor @Observable
final class PresenceSelectionModel {
    enum Pane: Hashable { case calendar, timeline }

    struct Selection: Equatable {
        let interval: ClosedRange<CalendarDay>
        let region: Region?
    }

    enum Item: Hashable {
        case recorded(RegionStint.ID)
        case flight(FlightAssessment.ID)
        case planned(PlanningTimelineItem.ID)

        init(_ item: PresenceJourneyItem) {
            self = switch item {
                case let .stay(stint): .recorded(stint.id)
                case let .flight(flight): .flight(flight.id)
            }
        }
    }

    struct Request: Identifiable {
        struct ID: Hashable { private let value = UUID() }
        let id = ID()
        let month: CalendarDay
        let item: Item?
    }

    private(set) var selection: Selection?
    private var request: Request?
    private var consumed: Set<Pane> = []

    var requestID: Request.ID? {
        request?.id
    }

    func pendingRequest(for pane: Pane) -> Request? {
        consumed.contains(pane) ? nil : request
    }

    func consume(_ requestID: Request.ID, by pane: Pane) {
        guard request?.id == requestID else { return }
        consumed.insert(pane)
    }

    func reset() {
        selection = nil
        request = nil
        consumed = []
    }

    private func select(_ selection: Selection, item: Item?) {
        self.selection = selection
        let start = selection.interval.lowerBound
        request = Request(
            month: CalendarDay(year: start.year, month: start.month, day: 1),
            item: item,
        )
        consumed = []
    }

    func select(month: CalendarDay, dateCalendar: Calendar) {
        let start = CalendarDay(year: month.year, month: month.month, day: 1)
        guard let interval = dateCalendar.dateInterval(
            of: .month,
            for: start.startOfDay(in: dateCalendar),
        ) else { return }
        let end = CalendarDay(from: interval.end, in: dateCalendar).adding(days: -1)
        select(Selection(interval: start ... end, region: nil), item: nil)
    }

    func select(stint: RegionStint, dateCalendar: Calendar) {
        let start = CalendarDay(from: stint.start, in: dateCalendar)
        let end = CalendarDay(from: stint.end, in: dateCalendar)
        select(Selection(interval: start ... end, region: stint.region), item: .recorded(stint.id))
    }

    func select(plannedItem: PlanningTimelineItem) {
        select(
            Selection(interval: plannedItem.start ... plannedItem.end, region: plannedItem.region),
            item: .planned(plannedItem.id),
        )
    }

    func selectedInterval(in year: Int) -> ClosedRange<CalendarDay>? {
        guard let selection, selection.interval.lowerBound.year <= year,
              selection.interval.upperBound.year >= year else { return nil }
        return max(selection.interval.lowerBound, CalendarDay(year: year, month: 1, day: 1))
            ... min(selection.interval.upperBound, .lastDay(ofYear: year))
    }

    /// Resolve against the rows actually displayed. An unresolved request remains pending while
    /// loading.
    func timelineTarget(
        recordedItems: [PresenceJourneyItem],
        plannedItems: [PlanningTimelineItem],
        calendar: Calendar,
    ) -> Item? {
        guard let request = pendingRequest(for: .timeline) else { return nil }
        if let item = request.item {
            return recordedItems.contains(where: { Item($0) == item })
                || plannedItems.contains(where: { .planned($0.id) == item }) ? item : nil
        }
        let start = request.month
        guard let interval = calendar.dateInterval(of: .month, for: start.startOfDay(in: calendar))
        else { return nil }
        let end = CalendarDay(from: interval.end, in: calendar).adding(days: -1)
        if let item = recordedItems.first(where: { item in
            switch item {
                case let .stay(stint):
                    CalendarDay(from: stint.start, in: calendar) <= end
                        && CalendarDay(from: stint.end, in: calendar) >= start
                case let .flight(flight):
                    flight.completedDays(in: calendar).contains { $0 >= start && $0 <= end }
            }
        }) { return Item(item) }
        return plannedItems.first { $0.start <= end && $0.end >= start }.map { .planned($0.id) }
    }
}
