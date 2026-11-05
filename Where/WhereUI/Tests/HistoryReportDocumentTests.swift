import Foundation
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct HistoryReportDocumentTests {
    @Test func copiesShareRetirementAndReturnOnlyTheAssessedBytes() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let csv = try await fixture.services.reports.exportableYearCSV(for: 2026)
        let document = HistoryReportDocument(
            report: csv,
            validate: fixture.services.validateDataAccess,
        )
        let copy = document
        #expect(try copy.exportedData() == csv.data)
        document.retire()
        #expect(throws: HistoryReportDocument.ExportError.retired) { try copy.exportedData() }
    }

    @Test func revokedCompatibilityBlocksTheSystemByteRequest() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let csv = try await fixture.services.reports.exportableYearCSV(for: 2026)
        let document = HistoryReportDocument(
            report: csv,
            validate: fixture.services.validateDataAccess,
        )
        await fixture.services.retireCompatibilityScope()
        #expect(throws: DataCompatibilityAccess.AccessError.revoked) { try document.exportedData() }
    }
}
