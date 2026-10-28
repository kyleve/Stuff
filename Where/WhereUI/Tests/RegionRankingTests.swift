import RegionKit
import Testing
import WhereCore
import WhereUI

struct RegionRankingTests {
    private func report(_ totals: [Region: Int]) -> YearReport {
        YearReport(year: 2026, days: [], totals: totals)
    }

    @Test func topTrackedRegionsArePrimary() {
        let ranking = RegionRanking(report: report([
            .california: 100,
            .newYork: 60,
            .canada: 20,
        ]))
        #expect(ranking.primary.map(\.region) == [.california, .newYork])
        #expect(ranking.secondary.map(\.region) == [.canada])
    }

    @Test func otherIsNeverPrimaryEvenWhenLargest() {
        let ranking = RegionRanking(report: report([
            .other: 200,
            .california: 30,
            .newYork: 10,
        ]))
        #expect(ranking.primary.map(\.region) == [.california, .newYork])
        #expect(ranking.secondary.map(\.region) == [.other])
    }

    @Test func onlyOtherDaysLeavePrimaryEmptyButRankingNonEmpty() {
        // Drives the Primary tab's "data exists, but not in a headline region"
        // empty state: `primary` is empty yet there's real tracked data.
        let ranking = RegionRanking(report: report([.other: 12]))
        #expect(ranking.primary.isEmpty)
        #expect(ranking.secondary.map(\.region) == [.other])
        #expect(!ranking.isEmpty)
    }

    @Test func zeroDayRegionsAreDropped() {
        let ranking = RegionRanking(report: report([
            .california: 5,
            .newYork: 0,
        ]))
        #expect(ranking.primary.map(\.region) == [.california])
        #expect(ranking.secondary.isEmpty)
    }

    @Test func tiesBreakByDeclarationOrder() {
        let ranking = RegionRanking(report: report([
            .canada: 40,
            .newYork: 40,
            .california: 40,
        ]))
        // California precedes New York precedes Canada in `Region.allCases`.
        #expect(ranking.primary.map(\.region) == [.california, .newYork])
        #expect(ranking.secondary.map(\.region) == [.canada])
    }

    @Test func emptyReportProducesEmptyRanking() {
        let ranking = RegionRanking(report: report([:]))
        #expect(ranking.isEmpty)
        #expect(ranking.primary.isEmpty)
        #expect(ranking.secondary.isEmpty)
    }

    @Test func dayCountsArePreserved() {
        let ranking = RegionRanking(report: report([.california: 148, .newYork: 96]))
        #expect(ranking.primary.first?.days == 148)
        #expect(ranking.primary.last?.days == 96)
    }

    @Test func primaryCountIsConfigurable() {
        let ranking = RegionRanking(
            report: report([.california: 100, .newYork: 60, .canada: 20]),
            primaryCount: 1,
        )
        #expect(ranking.primary.map(\.region) == [.california])
        #expect(ranking.secondary.map(\.region) == [.newYork, .canada])
    }
}
