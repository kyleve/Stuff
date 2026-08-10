import StuffToolCore
import Testing

struct XCStringsCommandTests {
    @Test func parserPreservesLintAndExplicitCatalogPaths() throws {
        let command = try XCStringsCommand.parse([
            "--lint",
            "Where/Where/Localizable.xcstrings",
            "Ledger/Ledger/Localizable.xcstrings",
        ])

        #expect(command.makeRequest() == XCStringsRequest(
            lint: true,
            paths: [
                "Where/Where/Localizable.xcstrings",
                "Ledger/Ledger/Localizable.xcstrings",
            ],
        ))
    }

    @Test func defaultsToRepositoryNormalizationAndRejectsUnknownFlags() throws {
        let command = try XCStringsCommand.parse([])
        #expect(command.makeRequest() == XCStringsRequest(lint: false, paths: []))
        #expect(throws: (any Error).self) {
            _ = try XCStringsCommand.parse(["--unknown"])
        }
    }
}
