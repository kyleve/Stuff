import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct DashboardProviderTests {
    private let token = SessionToken(cookieValue: "user_X::jwt")

    @Test func scriptedProviderReturnsItsScriptedSummaryAndInvoices() async throws {
        let provider = ScriptedDashboardProvider(.success(
            summary: .fixture(onDemandCents: 4200),
            invoiceCentsByMonth: [3: 5000],
        ))

        #expect(try await provider.usageSummary(token: token).onDemandCents == 4200)
        #expect(try await provider.monthlyInvoice(month: 3, year: 2026, token: token)
            .totalCents == 5000)
        // A month with no scripted value is a sparse (zero) invoice.
        #expect(try await provider.monthlyInvoice(month: 4, year: 2026, token: token)
            .totalCents == 0)
    }

    @Test func scriptedProviderThrowsItsFailureOutcome() async {
        let provider = ScriptedDashboardProvider(.failure(.notAuthenticated))
        await #expect(throws: DashboardError.notAuthenticated) {
            try await provider.usageSummary(token: token)
        }
    }

    @Test func scriptedProviderReturnsScriptedAggregatedUsage() async throws {
        let provider = ScriptedDashboardProvider(
            summary: .fixture(onDemandCents: 0),
        )
        // The convenience init supplies empty aggregation.
        let usage = try await provider.aggregatedUsage(startDate: .now, endDate: .now, token: token)
        #expect(usage.aggregations.isEmpty)
    }

    @Test func scriptedProviderCanFailOnlyAggregated() async throws {
        let provider = ScriptedDashboardProvider(
            .success(summary: .fixture(onDemandCents: 10), invoiceCentsByMonth: [:]),
            aggregatedFailure: .http(500),
        )
        // Summary still succeeds…
        _ = try await provider.usageSummary(token: token)
        // …while the per-model call fails.
        await #expect(throws: DashboardError.http(500)) {
            try await provider.aggregatedUsage(startDate: .now, endDate: .now, token: token)
        }
    }
}
