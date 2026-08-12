import Foundation
import StuffToolCore
import Testing

struct LoggedCommandRunnerTests {
    @Test func streamsBothOutputChannelsIntoTheRequestedLog() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "out\n", standardError: "error\n"),
        ])
        let log = root.appending(path: "command.log")

        let result = try await LoggedCommandRunner(
            runner: runner,
            fileSystem: FoundationFileSystem(),
        ).run(
            CommandInvocation(
                executable: "tool",
                arguments: [],
                environment: [:],
                workingDirectory: nil,
                standardInput: [],
                output: .streamed,
            ),
            logURL: log,
            outputHandler: nil,
        )

        #expect(result.succeeded)
        #expect(try String(contentsOf: log, encoding: .utf8) == "out\nerror\n")
    }
}
