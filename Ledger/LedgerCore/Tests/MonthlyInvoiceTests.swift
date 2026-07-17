import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct MonthlyInvoiceTests {
    @Test func decodesItemsAndSumsCents() throws {
        let invoice = try JSONDecoder().decode(
            MonthlyInvoice.self,
            from: Data(DashboardFixture.monthlyInvoiceJSON.utf8),
        )
        #expect(invoice.items?.count == 2)
        #expect(invoice.totalCents == 82811 + 33492)
    }

    @Test func aSparseInvoiceTotalsToZero() throws {
        let invoice = try JSONDecoder().decode(
            MonthlyInvoice.self,
            from: Data(DashboardFixture.emptyInvoiceJSON.utf8),
        )
        #expect(invoice.items == nil)
        #expect(invoice.totalCents == 0)
    }
}
