import Foundation
@testable import StuffToolCore
import Testing

struct XcodeWorkspaceTests {
    @Test func ownsGenerationLoggingAndBuildProductResolution() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let log = root.appending(path: "generate.log")
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "generated\n"),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
        ])
        let workspace = XcodeWorkspace(
            runner: runner,
            fileSystem: FoundationFileSystem(),
            repository: root,
            workspace: "Stuff.xcworkspace",
        )

        let generation = try await workspace.generateProject(logURL: log, outputHandler: nil)
        let products = try await workspace.builtProductsDirectory(
            scheme: "Stuff-iOS-Tests",
            destination: "platform=iOS Simulator,id=UDID",
            derivedData: root.appending(path: "DerivedData"),
        )

        #expect(generation.succeeded)
        #expect(workspace.checkoutIdentifier.count == 12)
        #expect(try String(contentsOf: log, encoding: .utf8) == "generated\n")
        #expect(products == "/tmp/Products")
        let invocations = await runner.invocations
        #expect(invocations[0].arguments == [
            "exec",
            "--",
            "tuist",
            "generate",
            "--no-open",
        ])
        #expect(invocations[0].output == .streamed)
        #expect(invocations[1].arguments.contains("-showBuildSettings"))
        #expect(invocations[1].arguments.contains(root.appending(path: "DerivedData").path))
    }

    @Test func exportsTypedResultDataAndProvidesLogTails() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let catalogData = try fixtureData("xcresult-tests", extension: "json")
        let summaryData = try fixtureData("xcresult-summary", extension: "json")
        let runner = FakeCommandRunner(responses: [
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(catalogData),
                standardError: [],
            ),
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(summaryData),
                standardError: [],
            ),
        ])
        let workspace = XcodeWorkspace(
            runner: runner,
            fileSystem: FoundationFileSystem(),
            repository: root,
            workspace: "Stuff.xcworkspace",
        )
        let testsJSON = root.appending(path: "tests.json")
        let summaryJSON = root.appending(path: "summary.json")

        let catalog = try await workspace.testCatalog(
            at: root.appending(path: "tests.xcresult"),
            exportingTo: testsJSON,
        )
        let summary = try await workspace.summary(
            at: root.appending(path: "tests.xcresult"),
            exportingTo: summaryJSON,
        )
        try Data("first\nsecond\nthird\n".utf8).write(to: root.appending(path: "run.log"))

        #expect(catalog.testCases.count == 2)
        #expect(summary.failedTests == 1)
        #expect(try Data(contentsOf: testsJSON) == catalogData)
        #expect(try workspace.logTail(at: root.appending(path: "run.log"), lines: 2) ==
            "third\n")
    }

    @Test func failedBuildSettingsLookupPreservesTheXcodebuildStatus() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let workspace = XcodeWorkspace(
            runner: FakeCommandRunner(responses: [.stub(exitCode: 72)]),
            fileSystem: FoundationFileSystem(),
            repository: root,
            workspace: "Stuff.xcworkspace",
        )

        do {
            _ = try await workspace.builtProductsDirectory(
                scheme: "Stuff-iOS-Tests",
                destination: "platform=iOS Simulator,id=UDID",
                derivedData: nil,
            )
            Issue.record("expected xcodebuild failure")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(72))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
