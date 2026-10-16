import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarNavigationModelTests {
    @Test func remountReissuesTheInitialMonthWhenNobodyHasBrowsedYet() {
        let navigation = CalendarNavigationModel()
        let month = CalendarDay(year: 2026, month: 7, day: 1)
        navigation.restorePosition(in: 2026, initialMonth: month)
        navigation.scrollPosition.scrollTo(edge: .top)
        navigation.restorePosition(in: 2026, initialMonth: month)
        #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == month)
    }

    @Test func waitsForTheRequestedYearBeforePositioning() {
        let navigation = CalendarNavigationModel()
        navigation.restorePosition(in: 2026, initialMonth: nil)
        navigation.restorePosition(
            in: 2026,
            initialMonth: CalendarDay(year: 2025, month: 12, day: 1),
        )
        #expect(navigation.initiallyPositionedYear == nil)
        let month = CalendarDay(year: 2026, month: 7, day: 1)
        navigation.restorePosition(in: 2026, initialMonth: month)
        #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == month)
    }

    @Test func remountUsesVisibleMonthWithoutReturningToToday() {
        let navigation = CalendarNavigationModel()
        let today = CalendarDay(year: 2026, month: 7, day: 1)
        let browsed = CalendarDay(year: 2026, month: 2, day: 1)
        navigation.restorePosition(in: 2026, initialMonth: today)
        navigation.recordVisibleMonths([browsed, today])
        navigation.restorePosition(in: 2026, initialMonth: today)
        #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == browsed)
    }

    @Test func staleVisibilityCannotOverrideANewYear() {
        let navigation = CalendarNavigationModel()
        let oldMonth = CalendarDay(year: 2025, month: 12, day: 1)
        let newMonth = CalendarDay(year: 2026, month: 7, day: 1)
        navigation.restorePosition(in: 2025, initialMonth: oldMonth)
        navigation.recordVisibleMonths([oldMonth])
        navigation.restorePosition(in: 2026, initialMonth: newMonth)
        navigation.recordVisibleMonths([oldMonth])
        #expect(navigation.visibleMonth == nil)
        #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == newMonth)
    }

    @Test func yearChangeConsumesStaleRevealWithoutReplacingItsIdentity() {
        let navigation = CalendarNavigationModel()
        navigation.reveal(month: CalendarDay(year: 2026, month: 2, day: 1))
        let request = navigation.revealRequest
        navigation.restorePosition(
            in: 2025,
            initialMonth: CalendarDay(year: 2025, month: 7, day: 1),
        )
        #expect(navigation.pendingReveal == nil)
        #expect(navigation.revealRequest == request)
        #expect(navigation.displayedMonth?.year == 2025)
    }

    @Test func visibilityDoesNotCreateScrollRequests() {
        let navigation = CalendarNavigationModel()
        let initial = CalendarDay(year: 2026, month: 7, day: 1)
        let browsed = CalendarDay(year: 2026, month: 2, day: 1)
        navigation.restorePosition(in: 2026, initialMonth: initial)
        navigation.recordVisibleMonths([browsed])
        #expect(navigation.visibleMonth == browsed)
        #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == initial)
    }
}
