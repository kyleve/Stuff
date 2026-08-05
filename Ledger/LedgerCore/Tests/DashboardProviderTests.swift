import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct DashboardProviderTests {
    private let token = SessionToken(cookieValue: "user_X::jwt")

    @Test func scriptedProviderReturnsItsScriptedSummary() async throws {
        let provider = ScriptedDashboardProvider(summary: .fixture(onDemandCents: 4200))
        #expect(try await provider.usageSummary(token: token).onDemandCents == 4200)
    }

    @Test func scriptedProviderThrowsItsFailureOutcome() async {
        let provider = ScriptedDashboardProvider(.failure(.notAuthenticated))
        await #expect(throws: DashboardError.notAuthenticated) {
            try await provider.usageSummary(token: token)
        }
    }

    @Test func scriptedProviderReturnsScriptedEvents() async throws {
        let provider = ScriptedDashboardProvider(
            .success(summary: .fixture(onDemandCents: 0)),
            events: UsageEventFixture.events(["a": 100]),
        )
        let page = try await provider.usageEvents(
            startDate: .now,
            endDate: .now,
            page: 1,
            pageSize: 250,
            token: token,
        )
        #expect(page.usageEventsDisplay.count == 1)
        #expect(page.totalUsageEventsCount == 1)
    }

    @Test func scriptedProviderCanFailOnlyEvents() async throws {
        let provider = ScriptedDashboardProvider(
            .success(summary: .fixture(onDemandCents: 10)),
            eventsFailure: .http(500),
        )
        // Summary still succeeds…
        _ = try await provider.usageSummary(token: token)
        // …while the per-model events call fails.
        await #expect(throws: DashboardError.http(500)) {
            try await provider.usageEvents(
                startDate: .now,
                endDate: .now,
                page: 1,
                pageSize: 250,
                token: token,
            )
        }
    }
}
