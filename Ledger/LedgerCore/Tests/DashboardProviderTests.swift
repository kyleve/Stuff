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
}
