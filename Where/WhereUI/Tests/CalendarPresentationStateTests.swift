import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarPresentationStateTests {
    @Test func unavailableDestinationsRejectWithoutChangingMode() {
        let state = CalendarPresentationState(mode: .overview)
        let july = CalendarDay(year: 2026, month: 7, day: 1)
        state.reconcile(year: 2026, availableMonths: [july], estimateMonth: nil)
        let initial = state.rejectionTrigger
        #expect(!state.expand(.estimate(july)))
        #expect(state.mode == .overview)
        let first = state.rejectionTrigger
        #expect(first != initial)
        #expect(!state.expand(.estimate(july)))
        #expect(state.rejectionTrigger != first)
        #expect(state.expand(.month(july)))
        state.mode = .overview
        state.reconcile(year: 2025, availableMonths: [], estimateMonth: nil)
        #expect(state.mode == .overview)
        #expect(state.rejectedTarget == nil)
    }
}
