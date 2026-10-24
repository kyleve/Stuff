import Foundation
import Testing
@testable import ThrowCore

struct TransitCSVTests {
    @Test func parserHandlesQuotedCommasEscapedQuotesAndCRLF() throws {
        let csv = try TransitCSV(data: Data(
            "id,name\r\n1,\"Canal, Street\"\r\n2,\"Say \"\"Hi\"\"\"\r\n".utf8,
        ))
        let rows = try csv.values()
        #expect(rows[0]["name"] == "Canal, Street")
        #expect(rows[1]["name"] == "Say \"Hi\"")
    }

    @Test func parserRejectsRowsWithTheWrongColumnCount() throws {
        let csv = try TransitCSV(data: Data("id,name\n1\n".utf8))
        #expect(throws: TransitDataError.invalidSchedule) { try csv.values() }
    }
}
