import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct UsageSummaryTests {
    @Test func decodesTheDashboardBodyIgnoringUnknownFields() throws {
        let summary = try JSONDecoder().decode(
            UsageSummary.self,
            from: Data(DashboardFixture.usageSummaryJSON.utf8),
        )

        #expect(summary.membershipType == "ultra")
        #expect(summary.onDemandCents == 315_609)
        #expect(summary.individualUsage.plan.used == 40000)
        #expect(summary.individualUsage.plan.limit == 40000)
        #expect(summary.individualUsage.plan.breakdown?.total == 52158)
        #expect(summary.individualUsage.onDemand.limit == nil)
    }

    @Test func exposesFirstPartyAndAPIPoolFractions() throws {
        let summary = try JSONDecoder().decode(
            UsageSummary.self,
            from: Data(DashboardFixture.usageSummaryJSON.utf8),
        )
        #expect(summary.autoFractionUsed == 0.0069)
        #expect(summary.apiFractionUsed == 1.0)
    }

    @Test func parsesFractionalSecondISO8601CycleDates() throws {
        let summary = try JSONDecoder().decode(
            UsageSummary.self,
            from: Data(DashboardFixture.usageSummaryJSON.utf8),
        )
        let start = try #require(summary.cycleStart)
        let end = try #require(summary.cycleEnd)
        #expect(end > start)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 4,
            hour: 18,
            minute: 16,
            second: 8,
        )))
        #expect(start == expected)
    }
}
