import Foundation
import WhereCore

/// An explicit month command. Repeating a destination creates a new request identity.
/// Keep the consumed request to display the selected month without replaying it on remount.
struct CalendarMonthReveal: Identifiable {
    struct ID: Hashable { private let value = UUID() }
    let id = ID()
    let month: CalendarDay
    var isPending = true

    init(month: CalendarDay) {
        self.month = CalendarDay(year: month.year, month: month.month, day: 1)
    }
}
