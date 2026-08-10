import StuffToolCore
import Testing

struct SimulatorCommandTests {
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
