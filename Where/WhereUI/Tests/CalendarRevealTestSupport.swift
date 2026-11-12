import Observation
import SwiftUI
import WhereCore
@testable import WhereUI

@MainActor @Observable
final class CalendarRevealTestSupport {
    var request: CalendarMonthReveal?

    var binding: Binding<CalendarMonthReveal?> {
        @Bindable var owner = self
        return $owner.request
    }

    func select(month: CalendarDay) {
        request = CalendarMonthReveal(month: month)
    }
}
