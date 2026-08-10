import Foundation
import StuffToolCore
import Testing

struct XCResultToolTests {
    @Test func requestsAndDecodesTestAndSummarySections() async throws {
        let tests = try fixtureData("xcresult-tests", extension: "json")
        let runner = FakeCommandRunner(responses: [
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(tests),
                standardError: [],
            ),
            .stub(standardOutput: "{\"failedTests\":2,\"passedTests\":8}"),
        ])
        let repository = URL(filePath: "/repo", directoryHint: .isDirectory)
        let tool = XCResultTool(runner: runner, repository: repository)
        let bundle = URL(filePath: "/tmp/tests.xcresult", directoryHint: .isDirectory)

        let catalog = try await tool.testCatalog(at: bundle)
        let summary = try await tool.summary(at: bundle)

        #expect(catalog.failures.count == 1)
        #expect(summary == XCResultSummary(failedTests: 2, passedTests: 8))
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments) == [
            ["xcresulttool", "get", "test-results", "tests", "--path", bundle.path],
            ["xcresulttool", "get", "test-results", "summary", "--path", bundle.path],
        ])
    }

    @Test func nonzeroToolExitIsTyped() async {
        let runner = FakeCommandRunner(responses: [
            .stub(exitCode: 1, standardError: "not a result bundle"),
        ])
        let bundle = URL(filePath: "/tmp/missing.xcresult", directoryHint: .isDirectory)
        let tool = XCResultTool(
            runner: runner,
            repository: URL(filePath: "/repo", directoryHint: .isDirectory),
        )

        await #expect(throws: XCResultToolFailure.commandFailed(
            path: bundle,
            detail: "not a result bundle",
        )) {
            _ = try await tool.testsData(at: bundle)
        }
    }
}
