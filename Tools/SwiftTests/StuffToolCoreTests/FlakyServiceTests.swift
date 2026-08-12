import Foundation
import StuffToolCore
import Testing

struct FlakyServiceTests {
    @Test func reportOnlyRunPreservesWarmBuildAndWritesTypedArtifacts() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "flaky", directoryHint: .isDirectory)
        let failed = try fixtureData("flaky-suite-failed", extension: "json")
        let repetitions = try fixtureData("flaky-tight-repetitions", extension: "json")
        let summary = try fixtureData("xcresult-summary", extension: "json")
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(standardOutput: "build log\n"),
            .stub(exitCode: 65, standardOutput: "suite failure\n"),
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(failed),
                standardError: [],
            ),
            .stub(exitCode: 65, standardOutput: "tight failure\n"),
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(repetitions),
                standardError: [],
            ),
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(summary),
                standardError: [],
            ),
        ])
        let terminal = MemoryTerminal()
        let service = FlakyService(
            runner: runner,
            simulator: StubFlakySimulator(udid: "FLAKY-UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            home: root,
            environment: ["FLAKY_WORKDIR": work.path],
        )

        let status = try await service.run(
            request(
                suiteRuns: 1,
                iterations: 2,
                relaunch: .no,
                updateReport: true,
            ),
        )

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 8)
        #expect(invocations[0].arguments == ["exec", "--", "tuist", "generate", "--no-open"])
        #expect(invocations[1].arguments.contains("-showBuildSettings"))
        #expect(invocations[2].arguments.contains("build-for-testing"))
        #expect(invocations[2].arguments.contains(work.appending(path: "DerivedData").path))
        #expect(invocations[3].arguments.contains("test-without-building"))
        #expect(invocations[3].arguments.contains("never"))
        #expect(invocations[3].environment == [
            "TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH": "/tmp/Products",
        ])
        #expect(invocations[3].output == .merged)
        #expect(invocations[5].arguments.contains(
            "-only-testing:StuffCoreTests/RaceTests/sometimesFails()",
        ))
        #expect(invocations[5].arguments.contains("NO"))
        #expect(invocations[7].arguments.contains("summary"))

        #expect(try String(
            contentsOf: work.appending(path: "suspects.txt"),
            encoding: .utf8,
        ) == "StuffCoreTests/RaceTests/sometimesFails()\n")
        #expect(try Data(contentsOf: work.appending(path: "suite/run_1.json")) == failed)
        #expect(try Data(contentsOf: work.appending(path: "tight/tight_1.tests.json")) ==
            repetitions)
        let report = try String(
            contentsOf: root.appending(path: "FLAKY_TESTS.md"),
            encoding: .utf8,
        )
        #expect(report.contains("1970-01-01T00:00:00Z"))
        #expect(report.contains("StuffCoreTests/RaceTests/sometimesFails()"))
        #expect(await terminal.standardOutputText.contains("75.0%"))
    }

    @Test func buildFailureIsTheChildStatusAndIncludesTheLogTail() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(exitCode: 72, standardError: "compile failed\n"),
        ])
        let terminal = MemoryTerminal()
        let service = makeService(root: root, runner: runner, terminal: terminal)

        do {
            _ = try await service.run(request(suiteRuns: 1, iterations: 2))
            Issue.record("expected the build failure")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(72))
        }
        #expect(await terminal.standardErrorText.contains("build failed (exit 72)"))
        #expect(await terminal.standardErrorText.contains("compile failed"))
    }

    @Test func resultInspectionFailureWarnsButDoesNotFailTheDetector() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(),
            .stub(exitCode: 65),
            .stub(exitCode: 1, standardError: "schema changed"),
        ])
        let terminal = MemoryTerminal()
        let service = makeService(root: root, runner: runner, terminal: terminal)

        let status = try await service.run(
            request(suiteRuns: 1, iterations: 2, updateReport: false),
        )

        #expect(status == 0)
        #expect(await terminal.standardErrorText.contains("could not read results for suite run 1"))
        #expect(await terminal.standardOutputText.contains("Phase 2: skipped"))
    }

    private func makeService(
        root: URL,
        runner: FakeCommandRunner,
        terminal: MemoryTerminal,
    ) -> FlakyService {
        FlakyService(
            runner: runner,
            simulator: StubFlakySimulator(udid: "UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            home: root,
            environment: ["FLAKY_WORKDIR": root.appending(path: "work").path],
        )
    }

    private func request(
        suiteRuns: Int,
        iterations: Int,
        relaunch: FlakyRelaunch = .yes,
        updateReport: Bool = true,
    ) -> FlakyRequest {
        FlakyRequest(
            suiteRuns: suiteRuns,
            iterations: iterations,
            device: "iPhone 17",
            os: "27.0",
            scheme: "Stuff-iOS-Tests",
            relaunch: relaunch,
            updateReport: updateReport,
            top: nil,
        )
    }
}

private actor StubFlakySimulator: SimulatorResolving {
    let udid: String

    init(udid: String) {
        self.udid = udid
    }

    func resolve(device _: String, os _: String, shared _: Bool) -> String {
        udid
    }
}
