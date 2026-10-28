import Foundation
import Testing
import WhereCore
@testable import WhereIntents

/// Guards that the intent layer's calendar stays aligned with the one
/// `WhereServices.forIntents()` aggregates in (`DayAggregator()`'s default).
/// If they drift, year/day queries silently return wrong or empty results.
struct CalendarWhereIntentsTests {
    @Test func isGregorianInTheCurrentTimeZone() {
        #expect(Calendar.whereIntents.identifier == .gregorian)
        #expect(Calendar.whereIntents.timeZone == .current)
    }

    @Test func matchesTheDayAggregatorDefault() {
        let aggregator = DayAggregator().calendar
        #expect(Calendar.whereIntents.identifier == aggregator.identifier)
        #expect(Calendar.whereIntents.timeZone == aggregator.timeZone)
    }
}
