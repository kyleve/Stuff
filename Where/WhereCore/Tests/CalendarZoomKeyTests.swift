import Testing
@testable import WhereCore

struct CalendarZoomKeyTests {
    @Test func builtInKeysKeepStableStorageNames() {
        #expect(CalendarZoomKey.year.rawValue == "year")
        #expect(CalendarZoomKey.region(.california).rawValue == "region.us-CA")
        #expect(CalendarZoomKey.region(.newYork).rawValue == "region.us-NY")
    }

    @Test func callersCanSupplyTheirOwnNamespace() {
        let key = CalendarZoomKey(rawValue: "travel-planner")
        #expect(key.rawValue == "travel-planner")
        #expect(key != .year)
    }
}
