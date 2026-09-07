import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct UsageEventsTests {
    @Test func decodesAPageIgnoringUnknownFields() throws {
        let page = try JSONDecoder().decode(
            UsageEventsPage.self,
            from: Data(DashboardFixture.usageEventsJSON.utf8),
        )
        #expect(page.totalUsageEventsCount == 40)
        #expect(page.usageEventsDisplay.count == 3)
        let first = try #require(page.usageEventsDisplay.first)
        #expect(first.model == "claude-opus-5-thinking-high")
        #expect(first.cents == 536.9)
    }

    @Test func sharesAggregatePerModelHighestFirst() {
        let events = [
            UsageEvent(model: "a", chargedCents: 30),
            UsageEvent(model: "b", chargedCents: 10),
            UsageEvent(model: "a", chargedCents: 10), // a totals 40
        ]
        let shares = ModelShare.shares(from: events)
        #expect(shares.map(\.name) == ["a", "b"])
        #expect(shares[0].fraction == 0.8) // 40 / 50
        #expect(shares[1].fraction == 0.2)
    }

    @Test func sharesIgnoreZeroAndNegativeCosts() {
        let events = [
            UsageEvent(model: "a", chargedCents: 100),
            UsageEvent(model: "free", chargedCents: 0),
            UsageEvent(model: "credit", chargedCents: -50),
        ]
        #expect(ModelShare.shares(from: events).map(\.name) == ["a"])
    }

    @Test func sharesAreEmptyWithoutChargedUsage() {
        #expect(ModelShare.shares(from: []).isEmpty)
        #expect(ModelShare.shares(from: [UsageEvent(model: "a", chargedCents: 0)]).isEmpty)
    }
}
