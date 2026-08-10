import StuffToolCore
import Testing

struct ProfileCommandTests {
    @Test func parserPreservesEveryCompatibilityOption() throws {
        let command = try ProfileCommand.parse([
            "--tests-only",
            "--no-snapshots",
            "--ci-shape",
            "--device",
            "iPhone 17 Pro",
            "--os",
            "27.1",
            "--top",
            "25",
            "--test-threshold",
            "0.2",
            "--typecheck-threshold",
            "150",
        ])

        #expect(command.makeRequest() == ProfileRequest(
            build: false,
            tests: true,
            snapshots: false,
            ciShape: true,
            device: "iPhone 17 Pro",
            os: "27.1",
            top: 25,
            testThreshold: 0.2,
            typeCheckThreshold: 150,
        ))
    }

    @Test func validationRejectsInvalidAndConflictingOptions() {
        #expect(throws: (any Error).self) {
            _ = try ProfileCommand.parse(["--build-only", "--tests-only"])
        }
        #expect(throws: (any Error).self) {
            _ = try ProfileCommand.parse(["--top", "0"])
        }
        #expect(throws: (any Error).self) {
            _ = try ProfileCommand.parse(["--test-threshold", "-1"])
        }
        #expect(throws: (any Error).self) {
            _ = try ProfileCommand.parse(["--typecheck-threshold", "-1"])
        }
        #expect(throws: (any Error).self) {
            _ = try ProfileCommand.parse(["--unknown"])
        }
    }
}
