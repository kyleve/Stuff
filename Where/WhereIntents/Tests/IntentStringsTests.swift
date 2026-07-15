import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereIntents

/// Pins the dialog copy's variant selection — the count-driven singular /
/// plural / none branches and the recent-activity states — which is where the
/// spoken results could silently go wrong.
struct IntentStringsTests {
    @Test func daysInRegionSelectsNoneSingularAndPlural() {
        let none = IntentStrings.daysInRegion(region: .california, days: 0, year: 2026)
        let one = IntentStrings.daysInRegion(region: .california, days: 1, year: 2026)
        let many = IntentStrings.daysInRegion(region: .california, days: 12, year: 2026)

        #expect(none.contains("no days"))
        #expect(one.contains("1 day"))
        #expect(many.contains("12 days"))
        // Region name comes from RegionKit, not a duplicated literal.
        #expect(many.contains(Region.california.localizedName))
    }

    @Test func loggedTripSelectsSingularAndPlural() {
        #expect(IntentStrings.loggedTrip(dayCount: 1, regions: [.newYork]).contains("1 day"))
        #expect(IntentStrings.loggedTrip(dayCount: 5, regions: [.newYork]).contains("5 days"))
    }

    @Test func recentActivityReturnsTheSummaryTextVerbatim() {
        let text = "You spent the week in California."
        #expect(IntentStrings.recentActivity(.summary(text), window: .week) == text)
    }

    @Test func recentActivityEmptyIsNonEmptyAndWindowSpecific() {
        let week = IntentStrings.recentActivity(.empty, window: .week)
        let month = IntentStrings.recentActivity(.empty, window: .month)
        #expect(!week.isEmpty)
        #expect(week != month)
    }

    @Test func unavailableReasonsProduceDistinctNonEmptyCopy() {
        let reasons: [ActivitySummaryUnavailableReason] = [
            .deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .unknown,
        ]
        let messages = reasons.map(IntentStrings.recentActivityUnavailable)
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(Set(messages).count == reasons.count)
    }
}
