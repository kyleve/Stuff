import RegionKit
import Testing
@testable import WhereCore

struct ElsewhereInputTests {
    @Test func eligibilityUsesConfiguredRegionsAndRecordedPresence() {
        let day = CalendarDay(year: 2026, month: 6, day: 1)
        let input = ElsewhereTestSupport.input(
            manualDays: [DayPresence(day: day, regions: [.california, .newYork, .canada])],
            primaryRegions: [.california, .newYork, .canada],
        )
        #expect(!input.hasVisits)
        #expect(!ElsewhereTestSupport.input().hasVisits)
        #expect(ElsewhereTestSupport.input(manualDays: [DayPresence(day: day, regions: [.other])])
            .hasVisits)
    }

    @Test func newCoordinatesChangeIdentityWithoutChangingAnnualTotals() {
        let first = ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)
        let before = ElsewhereTestSupport.input(samples: [first])
        let after = ElsewhereTestSupport.input(samples: [
            first,
            ElsewhereTestSupport.sample(ElsewhereTestSupport.portland),
        ])
        #expect(before.report == after.report)
        #expect(before != after)
    }
}
