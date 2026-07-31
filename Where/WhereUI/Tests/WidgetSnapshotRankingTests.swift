import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct WidgetSnapshotRankingTests {
    private static func snapshot(
        dayRegions: Set<Region>,
        totals: [Region: Int],
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            day: .now,
            year: 2026,
            dayRegions: dayRegions,
            totals: totals,
            appearances: [:],
            generatedAt: nil,
            surface: nil,
        )
    }

    @Test func rankedTotalsOrderAndCapMatchTheApp() {
        let snapshot = Self.snapshot(
            dayRegions: [],
            totals: [.california: 132, .newYork: 41, .canada: 9, .europeanUnion: 4, .other: 2],
        )
        let ranked = snapshot.rankedTotals(maxRows: 3)
        #expect(ranked.map(\.region) == [.california, .newYork, .canada])
        #expect(ranked.map(\.days) == [132, 41, 9])
    }

    @Test func orderedDayRegionsFollowDeclarationOrder() {
        let snapshot = Self.snapshot(
            dayRegions: [.other, .california, .canada],
            totals: [:],
        )
        #expect(snapshot.orderedDayRegions == [.california, .canada, .other])
    }
}
