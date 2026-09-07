import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereIntents

/// Pins the dialog copy's count-driven singular / plural / none branches,
/// which is where the spoken results could silently go wrong.
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
}
