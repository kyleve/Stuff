import Foundation
import Observation
import RegionKit
import WhereCore

/// Explicit selections connect history panes. Scroll observations never write this selection.
@MainActor @Observable
final class HistoryNavigationModel {
    struct Selection: Equatable {
        let interval: ClosedRange<CalendarDay>
        let region: Region?
    }

    let planning = PlanningPresentationModel()
    let calendar: CalendarNavigationModel
    let timeline = TimelineNavigationModel()
    private(set) var selection: Selection?

    init() {
        calendar = CalendarNavigationModel(planning: planning)
    }

    func select(month: CalendarDay, dateCalendar: Calendar) {
        let start = CalendarDay(year: month.year, month: month.month, day: 1)
        guard let interval = dateCalendar.dateInterval(
            of: .month,
            for: start.startOfDay(in: dateCalendar),
        )
        else { return }
        let end = CalendarDay(from: interval.end, in: dateCalendar).adding(days: -1)
        selection = Selection(interval: start ... end, region: nil)
        calendar.reveal(month: start)
        timeline.reveal(month: start)
    }

    func select(stint: RegionStint, dateCalendar: Calendar) {
        let start = CalendarDay(from: stint.start, in: dateCalendar)
        let end = CalendarDay(from: stint.end, in: dateCalendar)
        selection = Selection(interval: start ... end, region: stint.region)
        calendar.reveal(month: start)
        timeline.reveal(.recorded(stint.id))
    }

    func select(plannedItem: PlanningTimelineItem) {
        selection = Selection(
            interval: plannedItem.start ... plannedItem.end,
            region: plannedItem.region,
        )
        calendar.reveal(month: plannedItem.start)
        timeline.reveal(.planned(plannedItem.id))
    }

    func selectedInterval(in year: Int) -> ClosedRange<CalendarDay>? {
        guard let selection,
              selection.interval.lowerBound.year <= year,
              selection.interval.upperBound.year >= year
        else { return nil }
        let start = max(selection.interval.lowerBound, CalendarDay(year: year, month: 1, day: 1))
        let end = min(selection.interval.upperBound, .lastDay(ofYear: year))
        return start ... end
    }
}
