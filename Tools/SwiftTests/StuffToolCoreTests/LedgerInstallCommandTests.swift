import StuffToolCore
import Testing

struct LedgerInstallCommandTests {
    @Test func parserPreservesNoOpenAndAddsDryRun() throws {
        let command = try LedgerInstallCommand.parse(["--no-open", "--dry-run"])

        #expect(command.makeRequest() == LedgerInstallRequest(
            openAfterInstall: false,
            dryRun: true,
        ))
    }

    @Test func defaultsToInstallAndOpenAndRejectsUnknownArguments() throws {
        let command = try LedgerInstallCommand.parse([])
        #expect(command.makeRequest() == LedgerInstallRequest(
            openAfterInstall: true,
            dryRun: false,
        ))

        #expect(throws: (any Error).self) {
            _ = try LedgerInstallCommand.parse(["--unknown"])
        }
        #expect(throws: (any Error).self) {
            _ = try LedgerInstallCommand.parse(["positional"])
        }
    }
}
