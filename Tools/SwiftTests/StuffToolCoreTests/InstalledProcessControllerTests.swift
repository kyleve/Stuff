import Foundation
import StuffToolCore
import Testing

struct InstalledProcessControllerTests {
    @Test func parsesAndMatchesOnlyTheExactInstalledExecutable() async throws {
        let table = try fixtureData("process-table", extension: "txt")
        #expect(try InstalledProcessController.parseProcessTable(table) == [
            InstalledProcessRecord(
                processID: 101,
                executable: "/Applications/Ledger.app/Contents/MacOS/Ledger",
            ),
            InstalledProcessRecord(
                processID: 202,
                executable: "/tmp/DerivedData/Build/Products/Release/Ledger.app/Contents/MacOS/Ledger",
            ),
            InstalledProcessRecord(
                processID: 303,
                executable: "/Applications/Ledger.app/Contents/MacOS/LedgerHelper",
            ),
        ])
        let runner = FakeCommandRunner(responses: [
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(table),
                standardError: [],
            ),
            .stub(),
            .stub(standardOutput: ""),
        ])
        let controller = makeController(runner: runner, graceChecks: 1)

        let outcome = try await controller.terminate(
            executable: URL(filePath: "/Applications/Ledger.app/Contents/MacOS/Ledger"),
        )

        #expect(outcome == ProcessTerminationOutcome(
            matchedProcessIDs: [101],
            forcedProcessIDs: [],
        ))
        let invocations = await runner.invocations
        #expect(invocations[1].arguments == ["-TERM", "101"])
    }

    @Test func forceKillsOnlyExactProcessesThatOutliveTheGraceBound() async throws {
        let process = "  101 /Applications/Ledger.app/Contents/MacOS/Ledger\n"
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: process),
            .stub(),
            .stub(standardOutput: process),
            .stub(),
            .stub(standardOutput: ""),
        ])
        let clock = ImmediateClock()
        let controller = InstalledProcessController(
            runner: runner,
            clock: clock,
            repository: URL(filePath: "/repo"),
            policy: ProcessTerminationPolicy(
                graceChecks: 1,
                forceChecks: 1,
                interval: .milliseconds(100),
            ),
        )

        let outcome = try await controller.terminate(
            executable: URL(filePath: "/Applications/Ledger.app/Contents/MacOS/Ledger"),
        )

        #expect(outcome.forcedProcessIDs == [101])
        let invocations = await runner.invocations
        #expect(invocations[3].arguments == ["-KILL", "101"])
    }

    @Test func malformedOrFailedProcessInspectionFailsClosed() async throws {
        #expect(throws: InstalledProcessFailure.self) {
            _ = try InstalledProcessController.parseProcessTable(Data("not a record\n".utf8))
        }
        let runner = FakeCommandRunner(responses: [.stub(exitCode: 1)])
        let controller = makeController(runner: runner, graceChecks: 1)
        do {
            _ = try await controller.terminate(executable: URL(filePath: "/Applications/Ledger"))
            Issue.record("expected process inspection failure")
        } catch let failure as InstalledProcessFailure {
            #expect(failure == .exitCode(1))
        }
    }

    private func makeController(
        runner: FakeCommandRunner,
        graceChecks: Int,
    ) -> InstalledProcessController {
        InstalledProcessController(
            runner: runner,
            clock: ImmediateClock(),
            repository: URL(filePath: "/repo"),
            policy: ProcessTerminationPolicy(
                graceChecks: graceChecks,
                forceChecks: 1,
                interval: .milliseconds(100),
            ),
        )
    }
}
