import Foundation
import StuffToolCore
import Subprocess
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

    @Test func lintPrintsCatalogsBeforeTheSummaryWhenOutputIsCombined() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let catalog = directory.appending(path: "Localizable.xcstrings")
        try Data("{\"sourceLanguage\":\"en\",\"strings\":{}}\n".utf8).write(to: catalog)

        let result = try await Subprocess.run(
            .path(.init(prebuiltStuffExecutable.path)),
            arguments: ["xcstrings", "--lint", catalog.path],
            environment: .inherit.updating([
                "STUFF_REPOSITORY_ROOT": directory.path,
            ]),
            workingDirectory: .init(directory.path),
            output: .string(limit: .max),
            error: .combinedWithOutput,
        )

        #expect(result.terminationStatus == .exited(1))
        #expect(result.standardOutput.split(separator: "\n") == [
            "not normalized: Localizable.xcstrings",
            "1 catalog isn't normalized — run ./xcstrings",
        ])
    }
}
