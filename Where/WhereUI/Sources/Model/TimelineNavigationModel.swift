import Foundation
import Observation
import SwiftUI
import WhereCore

/// Scroll observations retain a local anchor. Only explicit selection requests reveal a row.
@MainActor @Observable
final class TimelineNavigationModel {
    /// Each explicit selection has its own identity. Consuming it keeps that
    /// identity stable, so the view does not observe its own response as a request.
    struct MonthReveal: Identifiable {
        struct ID: Hashable {
            private let value = UUID()
        }

        enum State {
            case pending(CalendarDay)
            case consumed
        }

        let id = ID()
        var state: State
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

    var scrollPosition = ScrollPosition(idType: Item.self)
    private(set) var visibleItem: Item?
    private var year: Int?
    private var monthReveal: MonthReveal?

    var monthRevealID: MonthReveal.ID? {
        monthReveal?.id
    }

    var requestedMonth: CalendarDay? {
        guard case let .pending(month) = monthReveal?.state else { return nil }
        return month
    }

    func restorePosition(in year: Int, initialItem: Item? = nil) {
        if self.year != year {
            let isChangingYear = self.year != nil
            self.year = year
            if isChangingYear { visibleItem = nil }
            if requestedMonth?.year != year { monthReveal = nil }
            if let visibleItem {
                scrollPosition.scrollTo(id: visibleItem, anchor: .center)
            } else if let initialItem {
                visibleItem = initialItem
                scrollPosition.scrollTo(id: initialItem, anchor: .center)
            } else {
                scrollPosition.scrollTo(edge: .bottom)
            }
        } else if let visibleItem {
            scrollPosition.scrollTo(id: visibleItem, anchor: .top)
        }
    }

    func recordVisibleItems(_ items: [Item], in year: Int) {
        guard self.year == year, let first = items.first else { return }
        visibleItem = first
    }

    func reveal(_ item: Item) {
        monthReveal = nil
        revealPosition(item)
    }

    private func revealPosition(_ item: Item) {
        visibleItem = item
        // Leading-edge alignment keeps the selected row visible after resizing.
        scrollPosition.scrollTo(id: item, anchor: .top)
    }

    func reveal(month: CalendarDay) {
        monthReveal = MonthReveal(state: .pending(month))
    }

    /// A month selected while data is loading is resolved when its rows arrive.
    func reconcile(
        recordedItems: [PresenceJourneyItem],
        plannedItems: [PlanningTimelineItem],
        calendar: Calendar,
    ) {
        guard let month = requestedMonth else { return }
        let start = CalendarDay(year: month.year, month: month.month, day: 1)
        guard let end = calendar.dateInterval(of: .month, for: start.startOfDay(in: calendar))
            .map({ CalendarDay(from: $0.end, in: calendar).adding(days: -1) })
        else { return }
        if let item = recordedItems.first(where: { item in
            switch item {
                case let .stay(stint):
                    CalendarDay(from: stint.start, in: calendar) <= end
                        && CalendarDay(from: stint.end, in: calendar) >= start
                case let .flight(flight):
                    flight.completedDays(in: calendar).contains { $0 >= start && $0 <= end }
            }
        }) {
            monthReveal?.state = .consumed
            revealPosition(Item(item))
        } else if let item = plannedItems.first(where: { $0.start <= end && $0.end >= start }) {
            monthReveal?.state = .consumed
            revealPosition(.planned(item.id))
        }
    }
}
