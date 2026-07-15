import RegionKit
import Testing
@testable import WhereIntents

struct IntentHelpersTests {
    @Test func orderedRegionsSortsByDeclarationOrder() {
        #expect(
            orderedRegions([.canada, .newYork, .california])
                == [.california, .newYork, .canada],
        )
        #expect(orderedRegions([]).isEmpty)
    }

    @Test func isCurrentYearComparesAgainstNow() {
        let calendar = IntentTestSupport.calendar()
        let now = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        #expect(isCurrentYear(2026, now: now, calendar: calendar))
        #expect(!isCurrentYear(2024, now: now, calendar: calendar))
        #expect(!isCurrentYear(2027, now: now, calendar: calendar))
    }
}
