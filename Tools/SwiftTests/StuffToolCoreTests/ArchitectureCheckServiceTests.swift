import Foundation
import StuffToolCore
import Testing

struct ArchitectureCheckServiceTests {
    @Test func runsTheCompleteSequenceWithDefaultsAndStreamsOutput() async throws {
        let repository = URL(filePath: "/repo", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "config ok\n"),
            .stub(standardOutput: "15 tests passed\n"),
            .stub(standardError: "lint timing\n"),
        ])
        let terminal = MemoryTerminal()
        let service = ArchitectureCheckService(
            runner: runner,
            terminal: terminal,
            repository: repository,
            environment: [:],
        )

        let status = try await service.run()

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments) == [
            ["run", "bumper", "config", "."],
            ["run", "bumper", "test", "."],
            ["run", "bumper", "lint", ".", "--timings"],
        ])
        #expect(invocations.allSatisfy { invocation in
            invocation.executable == "swift" &&
                invocation.environment == [
                    "BUMPER_CACHE_DIR": ".build/bumper-cache",
                    "BUMPER_RUNNER_BUILD_CONFIGURATION": "debug",
                ] &&
                invocation.workingDirectory == repository &&
                invocation.standardInput.isEmpty &&
                invocation.output == .streamed
        })
        #expect(await terminal.standardOutputText == """
        ==> Validating Bumper Bowling configuration
        config ok
        ==> Testing Bumper Bowling rules
        15 tests passed
        ==> Enforcing Where architecture

        """)
        #expect(await terminal.standardErrorText == "lint timing\n")
    }

    @Test func preservesOverridesAndStopsAtTheFirstFailure() async throws {
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(exitCode: 23, standardError: "rules failed\n"),
            .stub(),
        ])
        let terminal = MemoryTerminal()
        let service = ArchitectureCheckService(
            runner: runner,
            terminal: terminal,
            repository: URL(filePath: "/repo", directoryHint: .isDirectory),
            environment: [
                "BUMPER_CACHE_DIR": "/tmp/bumper",
                "BUMPER_RUNNER_BUILD_CONFIGURATION": "release",
            ],
        )

        let status = try await service.run()

        #expect(status == 23)
        let invocations = await runner.invocations
        #expect(invocations.count == 2)
        #expect(invocations[0].environment == [
            "BUMPER_CACHE_DIR": "/tmp/bumper",
            "BUMPER_RUNNER_BUILD_CONFIGURATION": "release",
        ])
        #expect(await terminal.standardErrorText == "rules failed\n")
        #expect(await terminal.standardOutputText.contains("Enforcing Where architecture") == false)
    }
}
