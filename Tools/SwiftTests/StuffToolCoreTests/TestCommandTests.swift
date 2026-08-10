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
            baseReference: "upstream/main",
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

    @Test func validationRejectsInvalidModesAndCombinations() {
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--record", "sometimes"])
        }
        #expect(throws: (any Error).self) {
            _ = try TestCommand.parse(["--all", "--everything"])
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
