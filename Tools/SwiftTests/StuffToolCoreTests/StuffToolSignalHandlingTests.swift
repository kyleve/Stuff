import Darwin
import Foundation
import StuffToolCore
import Subprocess
import System
import Testing

struct StuffToolSignalHandlingTests {
    @Test(.timeLimit(.minutes(1)))
    func directTerminationReachesTheWholeCommandTree() async throws {
        let fixture = try PublicShimProcessFixture()
        defer { fixture.cleanUp() }

        var platformOptions = PlatformOptions()
        platformOptions.createSession = true
        let result = try await Subprocess.run(
            .path(.init(fixture.whereInstall.path)),
            arguments: ["--yes"],
            environment: fixture.subprocessEnvironment(),
            workingDirectory: .init(fixture.repository.path),
            platformOptions: platformOptions,
            input: .none,
            output: .discarded,
            error: .discarded,
        ) { execution in
            let tree = try await waitForProcessTree(fixture)
            #expect(execution.processIdentifier.value == tree.stuff)
            try #require(
                Darwin.kill(tree.stuff, SIGTERM) == 0,
                "kill(\(tree.stuff), SIGTERM) failed with errno \(errno)",
            )
            return tree
        }

        #expect(result.terminationStatus == .signaled(SIGTERM))
        #expect(exitCode(for: result.terminationStatus) == 143)
        try await verifyTermination(
            result.closureResult,
            fixture: fixture,
            expectedChildSignal: "TERM",
            expectedGrandchildSignal: "TERM",
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func terminalControlCInterruptsTheWholeCommandTree() async throws {
        let fixture = try PublicShimProcessFixture()
        defer { fixture.cleanUp() }
        let exitStatusFile = fixture.temporaryDirectory.appending(path: "exit-status")

        var platformOptions = PlatformOptions()
        platformOptions.createSession = true
        let result = try await Subprocess.run(
            .path("/usr/bin/script"),
            arguments: [
                "-q",
                "/dev/null",
                "/bin/sh",
                "-c",
                """
                trap '' INT
                "$1" --yes
                status=$?
                printf '%s\\n' "$status" > "$2"
                exit "$status"
                """,
                "stuff-signal-wrapper",
                fixture.whereInstall.path,
                exitStatusFile.path,
            ],
            environment: fixture.subprocessEnvironment(),
            workingDirectory: .init(fixture.repository.path),
            platformOptions: platformOptions,
            input: .inputWriter,
            output: .discarded,
            error: .discarded,
        ) { execution in
            let tree = try await waitForProcessTree(fixture)
            _ = try await execution.standardInputWriter.write([0x03])
            try await execution.standardInputWriter.finish()
            return tree
        }

        #expect(exitCode(for: result.terminationStatus) == 130)
        #expect(try await waitForFileContents(at: exitStatusFile) == "130")
        try await verifyTermination(
            result.closureResult,
            fixture: fixture,
            expectedChildSignal: "INT",
            // POSIX shells start asynchronous jobs with SIGINT ignored. The
            // group teardown therefore reaches this fixture at SIGTERM.
            expectedGrandchildSignal: "TERM",
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedSignalForcesCleanupButPreservesTheFirstExitSignal() async throws {
        let fixture = try PublicShimProcessFixture()
        defer { fixture.cleanUp() }

        var platformOptions = PlatformOptions()
        platformOptions.createSession = true
        let result = try await Subprocess.run(
            .path(.init(fixture.whereInstall.path)),
            arguments: ["--yes"],
            environment: fixture.subprocessEnvironment(),
            workingDirectory: .init(fixture.repository.path),
            platformOptions: platformOptions,
            input: .none,
            output: .discarded,
            error: .discarded,
        ) { _ in
            let tree = try await waitForProcessTree(fixture)
            try #require(Darwin.kill(tree.stuff, SIGINT) == 0)
            #expect(try await waitForFileContents(at: fixture.childSignalFile) == "INT")
            try #require(Darwin.kill(tree.stuff, SIGTERM) == 0)
            return tree
        }

        #expect(exitCode(for: result.terminationStatus) == 130)
        try await verifyProcessExit(result.closureResult)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedOutputPipeTerminatesTheWholeCommandTree() async throws {
        let fixture = try PublicShimProcessFixture()
        defer { fixture.cleanUp() }

        var platformOptions = PlatformOptions()
        platformOptions.createSession = true
        let result = try await Subprocess.run(
            .path("/bin/bash"),
            arguments: [
                "-o",
                "pipefail",
                "-c",
                #""$1" --yes 2>&1 | /usr/bin/head -n 1"#,
                "stuff-closed-pipe",
                fixture.whereInstall.path,
            ],
            environment: fixture.subprocessEnvironment(writeOutput: true),
            workingDirectory: .init(fixture.repository.path),
            platformOptions: platformOptions,
            input: .none,
            output: .discarded,
            error: .discarded,
        ) { _ in
            try await waitForProcessTree(fixture)
        }

        #expect(exitCode(for: result.terminationStatus) == 141)
        try await verifyTermination(
            result.closureResult,
            fixture: fixture,
            expectedChildSignal: "PIPE",
            expectedGrandchildSignal: "PIPE",
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func hardDeadlineExitsWhileATerminalWriteRemainsBlocked() async throws {
        let fixture = try PublicShimProcessFixture()
        let outputPipe = try FullOutputPipe()
        defer {
            outputPipe.close()
            fixture.cleanUp()
        }

        var platformOptions = PlatformOptions()
        platformOptions.createSession = true
        let result = try await Subprocess.run(
            .path(.init(fixture.whereInstall.path)),
            arguments: ["--yes"],
            environment: fixture.subprocessEnvironment(writeOutput: true),
            workingDirectory: .init(fixture.repository.path),
            platformOptions: platformOptions,
            input: .none,
            output: .discarded,
            error: .fileDescriptor(
                FileDescriptor(rawValue: outputPipe.writeDescriptor),
                closeAfterSpawningProcess: false,
            ),
        ) { execution in
            let tree = try await waitForProcessTree(fixture)
            try #require(
                Darwin.kill(tree.stuff, SIGTERM) == 0,
                "kill(\(tree.stuff), SIGTERM) failed with errno \(errno)",
            )
            #expect(execution.processIdentifier.value == tree.stuff)
            return tree
        }

        #expect(exitCode(for: result.terminationStatus) == 143)
        try await verifyTermination(
            result.closureResult,
            fixture: fixture,
            expectedChildSignal: "TERM",
            expectedGrandchildSignal: "TERM",
        )
    }
}

private struct FixtureProcessTree {
    let stuff: pid_t
    let child: pid_t
    let grandchild: pid_t
}

private func waitForProcessTree(
    _ fixture: PublicShimProcessFixture,
) async throws -> FixtureProcessTree {
    async let stuff = waitForProcessID(in: fixture.stuffPIDFile)
    async let child = waitForProcessID(in: fixture.childPIDFile)
    async let grandchild = waitForProcessID(in: fixture.grandchildPIDFile)
    return try await FixtureProcessTree(
        stuff: stuff,
        child: child,
        grandchild: grandchild,
    )
}

private func verifyTermination(
    _ tree: FixtureProcessTree,
    fixture: PublicShimProcessFixture,
    expectedChildSignal: String,
    expectedGrandchildSignal: String,
) async throws {
    async let childSignal = waitForFileContents(at: fixture.childSignalFile)
    async let grandchildSignal = waitForFileContents(at: fixture.grandchildSignalFile)
    async let stuffExit: Void = waitForProcessExit(tree.stuff)
    async let childExit: Void = waitForProcessExit(tree.child)
    async let grandchildExit: Void = waitForProcessExit(tree.grandchild)

    let observedSignals = try await (childSignal, grandchildSignal)
    _ = try await (stuffExit, childExit, grandchildExit)

    #expect(observedSignals.0 == expectedChildSignal)
    #expect(observedSignals.1 == expectedGrandchildSignal)
}

private func verifyProcessExit(_ tree: FixtureProcessTree) async throws {
    async let stuffExit: Void = waitForProcessExit(tree.stuff)
    async let childExit: Void = waitForProcessExit(tree.child)
    async let grandchildExit: Void = waitForProcessExit(tree.grandchild)
    _ = try await (stuffExit, childExit, grandchildExit)
}

private func exitCode(for status: TerminationStatus) -> Int32 {
    switch status {
        case let .exited(code): code
        case let .signaled(signal): 128 + signal
    }
}
