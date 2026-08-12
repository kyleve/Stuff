import Darwin
import Foundation
import StuffToolCore
import Subprocess
import Testing

struct CommandRunnerTests {
    @Test func capturesStandardErrorAndExitStatus() async throws {
        let result = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/ls",
                arguments: ["/path/that/does/not/exist/stuff-tools"],
                environment: [:],
                workingDirectory: nil,
                standardInput: [],
                captureOutput: true,
                mergeStandardError: false,
            ),
        )

        #expect(result.terminationStatus == .exited(1))
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.isEmpty == false)
    }

    @Test func streamsHighVolumeWithoutLosingCapturedBytes() async throws {
        let recorder = OutputRecorder()
        let result = try await CommandRunner().run(
            CommandInvocation(
                executable: "/usr/bin/jot",
                arguments: ["-b", "0123456789", "20000"],
                environment: [:],
                workingDirectory: nil,
                standardInput: [],
                captureOutput: true,
                mergeStandardError: false,
            ),
            outputHandler: { stream, bytes in
                await recorder.record(stream, bytes: bytes)
            },
        )

        #expect(result.succeeded)
        #expect(result.standardOutput.count == 220_000)
        #expect(await recorder.standardOutput == result.standardOutput)
    }

    @Test func preservesNonUTF8Bytes() async throws {
        let result = try await CommandRunner().run(
            CommandInvocation(
                executable: "/usr/bin/printf",
                arguments: ["\\377"],
                environment: [:],
                workingDirectory: nil,
                standardInput: [],
                captureOutput: true,
                mergeStandardError: false,
            ),
        )

        #expect(result.standardOutput == [255])
    }

    @Test func mergesStreamsInChildWriteOrderWithoutRetainingOutput() async throws {
        let recorder = OutputRecorder()
        let result = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/sh",
                arguments: ["-c", "printf out; printf err >&2; printf end"],
                environment: [:],
                workingDirectory: nil,
                standardInput: [],
                captureOutput: false,
                mergeStandardError: true,
            ),
            outputHandler: { stream, bytes in
                await recorder.record(stream, bytes: bytes)
            },
        )

        #expect(result.succeeded)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.isEmpty)
        #expect(await String(decoding: recorder.standardOutput, as: UTF8.self) == "outerrend")
    }

    @Test func reportsChildSignals() async throws {
        let result = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/sh",
                arguments: ["-c", "kill -TERM $$"],
                environment: [:],
                workingDirectory: nil,
                standardInput: [],
                captureOutput: true,
                mergeStandardError: false,
            ),
        )

        #expect(result.terminationStatus == .signaled(15))
        #expect(result.exitCode == 143)
    }

    @Test func outputHandlerFailureTerminatesTheProcessTree() async throws {
        let fixture = try UncooperativeProcessTreeFixture()
        let gate = CancellationGate()
        defer { fixture.cleanUp() }

        let task = Task {
            try await CommandRunner().run(
                fixture.invocation,
                outputHandler: { _, _ in
                    await gate.wait()
                    throw OutputFailure.expected
                },
            )
        }
        defer { task.cancel() }
        let childProcessID = try await waitForProcessID(in: fixture.childPIDFile)
        let grandchildProcessID = try await waitForProcessID(in: fixture.grandchildPIDFile)
        try #require(isProcessAlive(childProcessID))
        try #require(isProcessAlive(grandchildProcessID))
        await gate.open()
        try await waitForProcessExit(grandchildProcessID)

        do {
            _ = try await task.value
            Issue.record("expected the output handler failure")
        } catch OutputFailure.expected {
            // Expected after the whole isolated process group has exited.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func cancellationTerminatesTheProcessTree() async throws {
        let fixture = try UncooperativeProcessTreeFixture()
        defer { fixture.cleanUp() }

        let task = Task {
            try await CommandRunner().run(fixture.invocation)
        }
        defer { task.cancel() }
        let childProcessID = try await waitForProcessID(in: fixture.childPIDFile)
        let grandchildProcessID = try await waitForProcessID(in: fixture.grandchildPIDFile)
        try #require(isProcessAlive(childProcessID))
        try #require(isProcessAlive(grandchildProcessID))

        task.cancel()
        try await waitForProcessExit(grandchildProcessID)

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // Expected after the whole isolated process group has exited.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func cancellationTerminatesTheTreeWhileAnOutputHandlerIsBlocked() async throws {
        let fixture = try UncooperativeProcessTreeFixture()
        let gate = CancellationGate()
        let (handlerEvents, handlerEventContinuation) = AsyncStream.makeStream(of: Void.self)
        defer {
            handlerEventContinuation.finish()
            fixture.cleanUp()
        }

        let task = Task {
            try await CommandRunner().run(
                fixture.invocation,
                outputHandler: { _, _ in
                    handlerEventContinuation.yield()
                    await gate.wait()
                },
            )
        }
        defer { task.cancel() }
        for await _ in handlerEvents {
            break
        }
        let childProcessID = try await waitForProcessID(in: fixture.childPIDFile)
        let grandchildProcessID = try await waitForProcessID(in: fixture.grandchildPIDFile)
        try #require(isProcessAlive(childProcessID))
        try #require(isProcessAlive(grandchildProcessID))

        task.cancel()
        try await waitForProcessExit(grandchildProcessID)
        await gate.open()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // Expected after the fallback killed the blocked handler's group.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func cancellationBeforeRunDoesNotSpawnTheChild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "CommandRunnerTests-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appending(path: "spawned")
        let gate = CancellationGate()
        let (entered, enteredSignal) = AsyncStream<Void>.makeStream()
        let task = Task {
            enteredSignal.yield()
            await gate.wait()
            return try await CommandRunner().run(
                CommandInvocation(
                    executable: "/usr/bin/touch",
                    arguments: [sentinel.path],
                    environment: [:],
                    workingDirectory: nil,
                    standardInput: [],
                    captureOutput: true,
                    mergeStandardError: false,
                ),
            )
        }

        for await _ in entered {
            break
        }
        task.cancel()
        await gate.open()
        enteredSignal.finish()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            #expect(FileManager.default.fileExists(atPath: sentinel.path) == false)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func passesEnvironmentWorkingDirectoryAndInput() async throws {
        let environment = try await CommandRunner().run(
            CommandInvocation(
                executable: "/usr/bin/printenv",
                arguments: ["STUFF_VALUE"],
                environment: ["STUFF_VALUE": "injected"],
                workingDirectory: nil,
                standardInput: [],
                captureOutput: true,
                mergeStandardError: false,
            ),
        )
        let workingDirectory = URL(filePath: "/private/tmp", directoryHint: .isDirectory)
        let directory = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/pwd",
                arguments: [],
                environment: [:],
                workingDirectory: workingDirectory,
                standardInput: [],
                captureOutput: true,
                mergeStandardError: false,
            ),
        )
        let input = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/cat",
                arguments: [],
                environment: [:],
                workingDirectory: nil,
                standardInput: Array("input".utf8),
                captureOutput: true,
                mergeStandardError: false,
            ),
        )

        #expect(environment.standardOutputText == "injected\n")
        #expect(directory.standardOutputText == "/private/tmp\n")
        #expect(input.standardOutputText == "input")
    }
}

private enum OutputFailure: Error {
    case expected
}

private struct UncooperativeProcessTreeFixture {
    let directory: URL
    let childPIDFile: URL
    let grandchildPIDFile: URL

    init() throws {
        directory = try makeTemporaryDirectory()
        childPIDFile = directory.appending(path: "child.pid")
        grandchildPIDFile = directory.appending(path: "grandchild.pid")
    }

    var invocation: CommandInvocation {
        CommandInvocation(
            executable: "/bin/sh",
            arguments: ["-c", Self.script],
            environment: [
                "STUFF_TEST_CHILD_PID_FILE": childPIDFile.path,
                "STUFF_TEST_GRANDCHILD_PID_FILE": grandchildPIDFile.path,
            ],
            workingDirectory: nil,
            standardInput: [],
            captureOutput: true,
            mergeStandardError: false,
        )
    }

    func cleanUp() {
        for file in [grandchildPIDFile, childPIDFile] {
            guard let processID = try? processID(in: file) else { continue }
            _ = Darwin.kill(processID, SIGKILL)
        }
        removeTemporaryDirectory(directory)
    }

    private func processID(in file: URL) throws -> pid_t {
        let value = try String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let processID = pid_t(value), processID > 0 else {
            throw UncooperativeProcessTreeFixtureError.invalidProcessID(file)
        }
        return processID
    }

    private static let script = """
    printf '%s\\n' "$$" > "$STUFF_TEST_CHILD_PID_FILE"
    /bin/sh -c '
        trap "" HUP INT QUIT TERM PIPE
        printf "%s\\n" "$$" > "$STUFF_TEST_GRANDCHILD_PID_FILE"
        exec /usr/bin/tail -f /dev/null
    ' &
    printf 'ready\\n'
    exec /usr/bin/tail -f /dev/null
    """
}

private enum UncooperativeProcessTreeFixtureError: Error {
    case invalidProcessID(URL)
}

private actor OutputRecorder {
    private(set) var standardOutput: [UInt8] = []

    func record(_ stream: CommandOutputStream, bytes: [UInt8]) {
        #expect(stream == .standardOutput)
        standardOutput.append(contentsOf: bytes)
    }
}

private actor CancellationGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard isOpen == false else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
