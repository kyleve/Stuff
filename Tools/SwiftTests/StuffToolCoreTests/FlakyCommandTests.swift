import StuffToolCore
import Testing

struct FlakyCommandTests {
    @Test func parserPreservesEveryCompatibilityOption() throws {
        let command = try FlakyCommand.parse([
            "--suite-runs",
            "3",
            "--iterations",
            "20",
            "--device",
            "iPhone 17 Pro",
            "--os",
            "27.1",
            "--scheme",
            "CustomTests",
            "--relaunch",
            "NO",
            "--no-update",
            "--top",
            "12",
        ])

        #expect(command.makeRequest() == FlakyRequest(
            suiteRuns: 3,
            iterations: 20,
            device: "iPhone 17 Pro",
            os: "27.1",
            scheme: "CustomTests",
            relaunch: .no,
            updateReport: false,
            top: 12,
        ))
    }

    @Test func dryRunAlsoSuppressesTheTrackedReportMutation() throws {
        let command = try FlakyCommand.parse(["--dry-run"])

        #expect(command.makeRequest().updateReport == false)
    }

    @Test func validationRejectsInvalidValues() {
        for arguments in [
            ["--suite-runs", "0"],
            ["--iterations", "0"],
            ["--top", "0"],
            ["--device", ""],
            ["--os", ""],
            ["--scheme", ""],
            ["--relaunch", "sometimes"],
            ["--unknown"],
        ] {
            #expect(throws: (any Error).self) {
                _ = try FlakyCommand.parse(arguments)
            }
        }
    }
}
