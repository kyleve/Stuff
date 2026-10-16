import Observation
import SwiftUI
import WhereCore

/// Retains the calendar's scroll anchor and requested planning presentation across remounts.
@MainActor @Observable
final class CalendarNavigationModel {
    private enum Anchor {
        case pending
        case initial(CalendarDay)
        case browsed(CalendarDay)

        var month: CalendarDay? {
            switch self {
                case .pending: nil
                case let .initial(month), let .browsed(month): month
            }
        }
    }

    var scrollPosition = ScrollPosition(idType: CalendarDay.self)
    let planning: PlanningPresentationModel
    var planningDestination: PlannedStaysDestination? {
        get { planning.destination }
        set { planning.destination = newValue }
    }

    private var anchor: Anchor = .pending

    init(planning: PlanningPresentationModel? = nil) {
        self.planning = planning ?? PlanningPresentationModel()
    }

    var displayedMonth: CalendarDay? {
        anchor.month
    }

    func reveal(month day: CalendarDay) {
        let month = CalendarDay(year: day.year, month: day.month, day: 1)
        anchor = .browsed(month)
        scrollPosition.scrollTo(id: month, anchor: .top)
    }

    var initiallyPositionedYear: Int? {
        anchor.month?.year
    }

    var visibleMonth: CalendarDay? {
        switch anchor {
            case .pending, .initial: nil
            case let .browsed(month): month
        }
    }

    /// A restored pane uses its last visible month. Only a new year uses the initial anchor.
    func restorePosition(in year: Int, initialMonth: CalendarDay?) {
        if initiallyPositionedYear == year {
            if let month = anchor.month, month.year == year {
                scrollPosition.scrollTo(id: month, anchor: .top)
            }
            return
        }
        guard let initialMonth, initialMonth.year == year else { return }
        // The section can include a forecast after its month. Align the start so
        // that extra content cannot move the requested month above the viewport.
        scrollPosition.scrollTo(id: initialMonth, anchor: .top)
        anchor = .initial(initialMonth)
    }

    /// Observing scrolling does not select an interval or move another pane.
    func recordVisibleMonths(_ months: [CalendarDay]) {
        guard let month = months.min(), month.year == initiallyPositionedYear else { return }
        anchor = .browsed(month)
    }
}
