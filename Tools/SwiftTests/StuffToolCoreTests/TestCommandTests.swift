import StuffToolCore
import Testing

struct TestCommandTests {
    @Test func parserPreservesCompatibilityOptions() throws {
        var command = try TestCommand.parse([
            "--snapshots",
            "--base",
            "upstream/main",
            "--no-build",
            "--no-generate",
            "--record",
            "missing",
            "--device",
            "iPhone 17 Pro",
            "--os",
            "27.1",
            "--shared",
            "--timings",
            "--review",
            "--heartbeat",
            "3.5",
            "--status-file",
            "status.txt",
        ])
        try command.validate()

        #expect(command.makeRequest() == TestRequest(
            scope: .snapshots,
            bundles: [],
            only: [],
            baseReference: "upstream/main",
            architectureMode: .run,
            build: false,
            generate: false,
            record: "missing",
            device: "iPhone 17 Pro",
            os: "27.1",
            sharedSimulator: true,
            timings: true,
            review: true,
            heartbeat: 3.5,
            statusFile: "status.txt",
        ))
    }

    @Test func parserSupportsRepeatableOnlyAndBundleScopes() throws {
        let only = try TestCommand.parse([
            "--only",
            "WhereCoreTests/CalendarDayTests",
            "--only",
            "WhereUITests/StylesheetTests",
        ])
        #expect(only.makeRequest().scope == .only)
        #expect(only.makeRequest().only.count == 2)

        let bundles = try TestCommand.parse(["WhereCoreTests", "WhereUITests"])
        #expect(bundles.makeRequest().scope == .bundles)
        #expect(bundles.makeRequest().bundles == ["WhereCoreTests", "WhereUITests"])
    }

    @Test func parserSelectsArchitectureOwnershipModes() throws {
        let normal = try TestCommand.parse([])
        #expect(normal.makeRequest().architectureMode == .run)

        let skipped = try TestCommand.parse(["--skip-architecture", "--all"])
        #expect(skipped.makeRequest().architectureMode == .skip)

        let only = try TestCommand.parse(["--architecture-only"])
        #expect(only.makeRequest().architectureMode == .only)
    }

    @Test func architectureOnlyRejectsEveryTestArgumentCategory() {
        let testArguments = [
            ["--all"],
            ["--snapshots"],
            ["--everything"],
            ["--only", "WhereCoreTests/Suite"],
            ["--base", "origin/main"],
            ["--no-build"],
            ["--no-generate"],
            ["--record", "never"],
            ["--device", "iPhone 17"],
            ["--os", "27.0"],
            ["--shared"],
            ["--timings"],
            ["--review"],
            ["--heartbeat", "15"],
            ["--status-file", "status.txt"],
            ["WhereCoreTests"],
        ]

        for arguments in testArguments {
            #expect(throws: (any Error).self) {
                _ = try TestCommand.parse(["--architecture-only"] + arguments)
            }
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--architecture-only", "--skip-architecture"])
        }
    }

    @Test func validationRejectsInvalidModesAndCombinations() {
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--record", "sometimes"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--all", "--everything"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["WhereCoreTests", "--all"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--heartbeat", "0"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--device", ""])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--only", ""])
        }
    }

    @Test func parserRejectsUnknownFlagsAndMissingValues() {
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--unknown"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--only"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--snapshot-shard", "1/2"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--timing-report", "timings.json"])
        }
    }
}
