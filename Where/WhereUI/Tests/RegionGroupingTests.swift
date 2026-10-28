import RegionKit
import Testing
@testable import WhereUI

/// The shared partition behind both region-selection surfaces.
struct RegionGroupingTests {
    private func region(_ id: String) throws -> Region {
        try #require(Region(rawValue: id))
    }

    @Test func partitionsPrimaryUsedAndOther() throws {
        let texas = try region("us-TX")
        let florida = try region("us-FL")
        let grouping = RegionGrouping(
            available: [.california, .newYork, texas, florida, .other],
            primary: [.california, .newYork],
            usedThisYear: [texas, .other],
        )
        // Primary keeps its given (pick) order; the rest follow `available`.
        #expect(grouping.primary == [.california, .newYork])
        // `.other` is excluded from used-this-year even when present.
        #expect(grouping.usedThisYear == [texas])
        #expect(grouping.other == [florida, .other])
    }

    @Test func primaryTakesPrecedenceOverUsedThisYear() throws {
        let texas = try region("us-TX")
        let grouping = RegionGrouping(
            available: [.california, texas, .other],
            primary: [.california],
            usedThisYear: [.california, texas],
        )
        #expect(grouping.primary == [.california])
        #expect(grouping.usedThisYear == [texas])
        #expect(grouping.other == [.other])
    }

    @Test func primaryIsFilteredToAvailableAndKeepsOrder() throws {
        let texas = try region("us-TX")
        let grouping = RegionGrouping(
            available: [.california, .newYork, texas],
            // NY first, then a region not offered (dropped), then CA.
            primary: [.newYork, .canada, .california],
            usedThisYear: [],
        )
        #expect(grouping.primary == [.newYork, .california])
        #expect(grouping.other == [texas])
    }

    @Test func flagsWhenNothingPrecedesOther() {
        let empty = RegionGrouping(available: [.california], primary: [], usedThisYear: [])
        #expect(empty.hasNoGroupsBeforeOther)

        let withPrimary = RegionGrouping(
            available: [.california],
            primary: [.california],
            usedThisYear: [],
        )
        #expect(!withPrimary.hasNoGroupsBeforeOther)
    }
}
