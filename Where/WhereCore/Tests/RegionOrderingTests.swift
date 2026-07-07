import RegionKit
import Testing
import WhereCore

struct RegionOrderingTests {
    // MARK: - declarationOrder

    @Test func declarationOrderMatchesAllCasesIndices() {
        for (index, region) in Region.allCases.enumerated() {
            #expect(Region.declarationOrder[region] == index)
        }
        #expect(Region.declarationOrder.count == Region.allCases.count)
    }

    // MARK: - rankedByDayCount

    @Test func rankedByDayCountOrdersByDaysDescending() {
        let ranked = Region.rankedByDayCount(
            [
                RegionDayTally(region: .newYork, days: 3),
                RegionDayTally(region: .california, days: 10),
                RegionDayTally(region: .canada, days: 7),
            ],
            days: \.days,
            region: \.region,
        )
        #expect(ranked.map(\.region) == [.california, .canada, .newYork])
    }

    @Test func tiesBreakByDeclarationOrderNotInputOrder() {
        // `canada` is listed first but `california` outranks it on a tie because
        // it comes earlier in `Region.allCases`; likewise `newYork` before
        // `other`.
        let ranked = Region.rankedByDayCount(
            [
                RegionDayTally(region: .canada, days: 10),
                RegionDayTally(region: .california, days: 10),
                RegionDayTally(region: .other, days: 5),
                RegionDayTally(region: .newYork, days: 5),
            ],
            days: \.days,
            region: \.region,
        )
        #expect(ranked.map(\.region) == [.california, .canada, .newYork, .other])
    }

    /// The daily-summary path ranks `[Region: Int]` entries directly, so the
    /// helper has to work on dictionary elements as well as named rows.
    @Test func ranksDictionaryEntriesWithDeterministicTieBreak() {
        let totals: [Region: Int] = [.canada: 8, .california: 8, .newYork: 20]
        let ranked = Region.rankedByDayCount(
            totals,
            days: { $0.value },
            region: { $0.key },
        )
        #expect(ranked.map(\.key) == [.newYork, .california, .canada])
        #expect(ranked.map(\.value) == [20, 8, 8])
    }
}
