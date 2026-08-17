import Foundation
@testable import StuffToolCore
import Testing

struct TestArtifactsTests {
    @Test func resolvesCreatesEnumeratesAndMeasuresThroughTypedArgv() async throws {
        let repository = URL(filePath: "/repo", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: """
            {"products":"/artifacts/Products","schemes":{"StuffSnapshotTests":"/artifacts/tests.xctestrun"}}
            """),
            .stub(standardOutput: "manifest created\n"),
            .stub(standardOutput: "suites written\n"),
            .stub(standardOutput: "123\t/artifacts/DerivedData/Build/Products\n"),
        ])
        let terminal = MemoryTerminal()
        let service = TestArtifactService(
            runner: runner,
            terminal: terminal,
            repository: repository,
        )
        let root = URL(filePath: "/artifacts", directoryHint: .isDirectory)

        let paths = try await service.resolve(root: root, schemes: ["StuffSnapshotTests"])
        let createStatus = try await service.create(root: root, schemes: ["StuffSnapshotTests"])
        let suitesStatus = try await service.writeSuites(
            input: URL(filePath: "/tmp/raw.json"),
            output: URL(filePath: "/tmp/suites.txt"),
        )
        let bytes = try await service.productBytes(root: root)

        #expect(paths == TestArtifactPaths(
            products: "/artifacts/Products",
            schemes: ["StuffSnapshotTests": "/artifacts/tests.xctestrun"],
        ))
        #expect(createStatus == 0)
        #expect(suitesStatus == 0)
        #expect(bytes == 123 * 1024)
        let invocations = await runner.invocations
        #expect(invocations.map(\.executable) == ["python3", "python3", "python3", "du"])
        #expect(invocations[0].arguments == [
            ".circleci/test_artifacts.py",
            "resolve-all",
            "--root",
            "/artifacts",
            "--scheme",
            "StuffSnapshotTests",
        ])
        #expect(await terminal.standardOutputText == "manifest created\nsuites written\n")
    }

    @Test func helperFailureIsObservableAndPreservesItsStatus() async throws {
        let runner = FakeCommandRunner(responses: [
            .stub(exitCode: 23, standardError: "error: invalid artifacts\n"),
        ])
        let terminal = MemoryTerminal()
        let service = TestArtifactService(
            runner: runner,
            terminal: terminal,
            repository: URL(filePath: "/repo", directoryHint: .isDirectory),
        )

        do {
            _ = try await service.resolve(
                root: URL(filePath: "/artifacts", directoryHint: .isDirectory),
                schemes: ["StuffSnapshotTests"],
            )
            Issue.record("expected artifact validation to fail")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(23))
        }
        #expect(await terminal.standardErrorText == "error: invalid artifacts\n")
    }
}
