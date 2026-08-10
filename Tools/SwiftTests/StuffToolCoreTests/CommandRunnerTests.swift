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
            ),
        )

        #expect(result.terminationStatus == .signaled(15))
        #expect(result.exitCode == 143)
    }

    @Test func outputHandlerFailureTerminatesTheChild() async {
        do {
            _ = try await CommandRunner().run(
                CommandInvocation(executable: "/usr/bin/yes"),
                outputHandler: { _, _ in throw OutputFailure.expected },
            )
            Issue.record("expected the output handler failure")
        } catch OutputFailure.expected {
            // Expected: the runner tears down the still-producing child first.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func cancellationTerminatesTheChild() async {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await CommandRunner().run(
                CommandInvocation(executable: "/usr/bin/yes"),
                outputHandler: { _, _ in signal.yield() },
            )
        }

        for await _ in started {
            break
        }
        task.cancel()
        signal.finish()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // Expected.
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
            ),
        )
        let workingDirectory = URL(filePath: "/private/tmp", directoryHint: .isDirectory)
        let directory = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/pwd",
                workingDirectory: workingDirectory,
            ),
        )
        let input = try await CommandRunner().run(
            CommandInvocation(
                executable: "/bin/cat",
                standardInput: Array("input".utf8),
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

private actor OutputRecorder {
    private(set) var standardOutput: [UInt8] = []

    func record(_ stream: CommandOutputStream, bytes: [UInt8]) {
        #expect(stream == .standardOutput)
        standardOutput.append(contentsOf: bytes)
    }
}
