import StuffToolCore
import Testing

struct WhereInstallCommandTests {
    @Test func parserPreservesEveryCompatibilityOptionAndDryRun() throws {
        let command = try WhereInstallCommand.parse([
            "--device",
            "Kai's iPhone",
            "--configuration",
            "Release",
            "--no-optimize",
            "--cloudkit",
            "--no-launch",
            "--yes",
            "--dry-run",
        ])

        #expect(try command.makeRequest() == WhereInstallRequest(
            device: "Kai's iPhone",
            configuration: "Release",
            optimize: false,
            cloudKit: true,
            launch: false,
            assumeYes: true,
            dryRun: true,
        ))
    }

    @Test func optimizeFlagsChooseTheLastValueLikeTheShellParser() throws {
        let enabled = try WhereInstallCommand.parse(["--no-optimize", "--optimize"])
        #expect(try enabled.makeRequest().optimize)

        let disabled = try WhereInstallCommand.parse(["--optimize", "--no-optimize"])
        #expect(try disabled.makeRequest().optimize == false)
    }

    @Test func validatesValuesAndRejectsUnknownOptions() throws {
        for arguments in [
            ["--configuration", ""],
            ["--configuration", "../Release"],
            ["--device", ""],
        ] {
            let command = try WhereInstallCommand.parse(arguments)
            #expect(throws: WhereInstallFailure.self) {
                _ = try command.makeRequest()
            }
        }
        #expect(throws: (any Error).self) {
            _ = try WhereInstallCommand.parse(["--unknown"])
        }
        #expect(throws: (any Error).self) {
            _ = try WhereInstallCommand.parse(["--configuration"])
        }
    }
}
