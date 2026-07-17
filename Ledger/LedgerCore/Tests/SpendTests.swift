import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct SpendTests {
    @Test func decodesTheDocumentedResponseIgnoringUnknownFields() throws {
        let data = Data(SpendFixture.responseJSON.utf8)
        let response = try JSONDecoder().decode(SpendResponse.self, from: data)

        #expect(response.teamMemberSpend.count == 2)
        #expect(response.subscriptionCycleStart == 1_708_992_000_000)

        let alex = try #require(response.teamMemberSpend.first)
        #expect(alex.email == "alex@company.com")
        // Sub-cent precision survives (the fields are Double, not Int).
        #expect(alex.spendCents == 4212.5)
        #expect(alex.includedSpendCents == 8000)
        #expect(alex.overallSpendCents == 12212.5)
        #expect(alex.fastPremiumRequests == 143)
    }

    @Test func matchesMemberByEmailCaseInsensitively() throws {
        let data = Data(SpendFixture.responseJSON.utf8)
        let response = try JSONDecoder().decode(SpendResponse.self, from: data)

        #expect(response.member(matching: "ALEX@company.com")?.userId == "user_ABC")
        #expect(response.member(matching: " blair@company.com ")?.userId == "user_DEF")
        #expect(response.member(matching: "nobody@company.com") == nil)
        #expect(response.member(matching: "") == nil)
    }

    @Test func totalPrefersOverallSpendWhenPresent() {
        let member = SpendFixture.member(
            email: "a@b.com",
            spendCents: 100,
            includedSpendCents: 200,
            overallSpendCents: 999,
        )
        #expect(member.totalCents == 999)
        #expect(member.totalDollars == 9.99)
    }

    @Test func totalFallsBackToOnDemandPlusIncludedWhenOverallAbsent() {
        let member = SpendFixture.member(
            email: "a@b.com",
            spendCents: 100,
            includedSpendCents: 200,
            overallSpendCents: nil,
        )
        #expect(member.totalCents == 300)
        #expect(member.onDemandDollars == 1)
        #expect(member.includedDollars == 2)
    }

    @Test func totalFallsBackToOnDemandOnlyWhenIncludedAlsoAbsent() {
        let member = SpendFixture.member(email: "a@b.com", spendCents: 250)
        #expect(member.totalCents == 250)
        #expect(member.includedDollars == nil)
    }
}
