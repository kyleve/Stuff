import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct AggregatedUsageTests {
    @Test func decodesStringTokenCounts() throws {
        let usage = try JSONDecoder().decode(
            AggregatedUsage.self,
            from: Data(DashboardFixture.aggregatedJSON.utf8),
        )
        #expect(usage.aggregations.count == 2)
        let opus = try #require(usage.aggregations.first)
        #expect(opus.modelIntent == "claude-opus-4-8-thinking-xhigh")
        #expect(opus.totalCents == 28929.15)
        #expect(opus.tier == 1)
        // 1846267 + 2088128 + 12919376 + 316915979
        #expect(opus.totalTokens == 333_769_750)
    }

    @Test func topModelsAreSharesSortedByCostHighestFirst() {
        let usage = AggregatedUsage.fixture([
            "b": 25,
            "a": 75,
        ])
        let top = usage.topModels(limit: 5)
        #expect(top.map(\.name) == ["a", "b"])
        #expect(top[0].fraction == 0.75)
        #expect(top[1].fraction == 0.25)
    }

    @Test func topModelsRespectsTheLimit() {
        let usage = AggregatedUsage.fixture(["a": 4, "b": 3, "c": 2, "d": 1])
        #expect(usage.topModels(limit: 2).map(\.name) == ["a", "b"])
    }

    @Test func topModelsIsEmptyWhenNoUsage() {
        #expect(AggregatedUsage(aggregations: [], totalCostCents: 0).topModels(limit: 5).isEmpty)
    }
}
