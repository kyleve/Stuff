import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct WidgetSnapshotRankingTests {
    private static func snapshot(
        dayRegions: Set<Region>,
        totals: [Region: Int],
    ) -> WidgetSnapshot {
        WidgetSnapshot(day: .now, year: 2026, dayRegions: dayRegions, totals: totals)
    }

    @Test func rankedTotalsOrderAndCapMatchTheApp() {
        let snapshot = Self.snapshot(
            dayRegions: [],
            totals: [.california: 132, .newYork: 41, .ontario: 9, .europeanUnion: 4, .other: 2],
        )
        let ranked = snapshot.rankedTotals(maxRows: 3)
        #expect(ranked.map(\.region) == [.california, .newYork, .ontario])
        #expect(ranked.map(\.days) == [132, 41, 9])
    }

    @Test func cachedCountryIDsAreOmittedFromWidgetRows() throws {
        let country = try JSONDecoder().decode(Region.self, from: Data(#""canada""#.utf8))
        let snapshot = Self.snapshot(
            dayRegions: [country, .ontario, .other],
            totals: [country: 20, .ontario: 5, .europeanUnion: 2],
        )
        #expect(snapshot.orderedDayRegions == [.ontario, .other])
        #expect(snapshot.rankedTotals(maxRows: 3).map(\.region) == [.ontario, .europeanUnion])
    }

    @Test func orderedDayRegionsFollowDeclarationOrder() {
        let snapshot = Self.snapshot(
            dayRegions: [.other, .california, .ontario],
            totals: [:],
        )
        #expect(snapshot.orderedDayRegions == [.california, .ontario, .other])
    }
}
