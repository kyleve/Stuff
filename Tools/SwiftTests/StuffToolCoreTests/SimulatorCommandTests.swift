import StuffToolCore
import Testing

struct SimulatorCommandTests {
    @Test func simulatorFailuresMapToTheirCompatibilityExitStatus() {
        #expect(SimulatorFailure.message("bad input").exitStatus == 1)
        #expect(SimulatorFailure.reported.exitStatus == 1)
        #expect(SimulatorFailure.exitCode(23).exitStatus == 23)
    }

    @Test func parserAcceptsEveryCompatibilityFlag() throws {
        _ = try SimulatorCommand.parse([
            "--device",
            "iPhone 17 Pro",
            "--os",
            "27.0",
            "--no-boot",
            "--shared",
        ])
        _ = try SimulatorCommand.parse(["--list"])
        _ = try SimulatorCommand.parse(["--prune", "--dry-run"])
        _ = try SimulatorCommand.parse(["--delete", "--dry-run"])
        _ = try SimulatorCommand.parse(["--recreate", "--dry-run"])
    }

    @Test func parserRejectsUnknownFlagsAndMissingOptionValues() {
        #expect(throws: (any Error).self) {
            _ = try SimulatorCommand.parse(["--unknown"])
        }
        #expect(throws: (any Error).self) {
            _ = try SimulatorCommand.parse(["--device"])
        }
    }
}
