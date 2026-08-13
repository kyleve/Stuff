import Foundation
import StuffToolCore
import Testing

struct TestServiceTests {
    @Test func orchestratesGenerateBuildAndTestWithTypedInvocations() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "work", directoryHint: .isDirectory)
        let testOutput = """
        ◇ Test run started.
        ◇ Suite ExampleTests started.
        ◇ Test works() started.
        ✔ Test works() passed after 0.001 seconds.
        ** TEST SUCCEEDED **

        """
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "backup passed\n"),
            .stub(standardOutput: "generated\n"),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Build/Products\n"),
            .stub(standardOutput: "built\n"),
            .stub(standardOutput: testOutput),
        ])
        let simulator = StubSimulatorResolver(udid: "TEST-UDID")
        let terminal = MemoryTerminal()
        let service = TestService(
            runner: runner,
            simulator: simulator,
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": work.path],
        )

        let status = try await service.run(
            makeTestRequest(
                scope: .all,
                record: "missing",
                timings: true,
                review: true,
            ),
        )

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 5)
        #expect(invocations[0].executable == "mise")
        #expect(invocations[0].arguments == [
            "exec",
            "--",
            "ruby",
            "Where/Tools/Tests/upgrade_backup_test.rb",
        ])
        #expect(invocations[1].arguments == [
            "exec",
            "--",
            "tuist",
            "generate",
            "--no-open",
        ])
        #expect(invocations[2].arguments.contains("-showBuildSettings"))
        #expect(invocations[3].arguments.first == "build-for-testing")
        let test = invocations[4]
        #expect(test.arguments == [
            "test-without-building",
            "-workspace",
            "Stuff.xcworkspace",
            "-scheme",
            "Stuff-iOS-Tests",
            "-destination",
            "platform=iOS Simulator,id=TEST-UDID",
            "-resultBundlePath",
            work.appending(path: "Stuff-iOS-Tests.xcresult").path,
            "-collect-test-diagnostics",
            "never",
        ])
        #expect(test.environment == [
            "TEST_RUNNER_SNAPSHOT_RECORD": "missing",
            "TEST_RUNNER_SNAPSHOT_TIMING": "1",
            "TEST_RUNNER_SNAPSHOT_DIFF": "1",
            "TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH": "/tmp/Build/Products",
        ])
        #expect(test.output == .merged)
        #expect(try String(
            decoding: Data(contentsOf: work.appending(path: "Stuff-iOS-Tests.log")),
            as: UTF8.self,
        ) == testOutput)
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: work.path)[.posixPermissions] as? Int,
        )
        #expect(permissions == 0o700)
        #expect(await terminal.standardOutputText.contains("==> Passed."))
        #expect(await simulator.calls == [
            .init(device: "iPhone 17", os: "27.0", shared: false),
        ])
    }

    @Test func successfulXcodebuildThatMatchesZeroTestsFails() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(standardOutput: "** TEST SUCCEEDED **\n"),
        ])
        let terminal = MemoryTerminal()
        let service = TestService(
            runner: runner,
            simulator: StubSimulatorResolver(udid: "UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": root.appending(path: "work").path],
        )

        let status = try await service.run(
            makeTestRequest(scope: .all, build: false, generate: false),
        )

        #expect(status == 1)
        #expect(await terminal.standardOutputText.contains("nothing ran"))
        #expect(await terminal.standardOutputText.contains("==> Failed (exit 1)."))
    }

    @Test func changedScopeStopsBeforeGraphAndSimulatorWhenTreeIsClean() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "base\n"),
            .stub(standardOutput: "abcdef\n"),
            .stub(),
            .stub(),
            .stub(),
        ])
        let simulator = StubSimulatorResolver(udid: "UNUSED")
        let terminal = MemoryTerminal()
        let service = TestService(
            runner: runner,
            simulator: simulator,
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": root.appending(path: "work").path],
        )

        let status = try await service.run(makeTestRequest(scope: .changed))

        #expect(status == 0)
        #expect(await runner.invocations.count == 6)
        #expect(await simulator.calls.isEmpty)
        #expect(await terminal.standardOutputText.contains(
            "No changes against origin/main — nothing to test.",
        ))
    }

    @Test func createsTheTuistGraphOutputDirectoryBeforeInvocation() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "work", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(exitCode: 1, standardError: "graph failed"),
        ])
        let service = TestService(
            runner: runner,
            simulator: StubSimulatorResolver(udid: "UNUSED"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: MemoryTerminal(),
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": work.path],
        )

        do {
            _ = try await service.run(
                makeTestRequest(scope: .bundles, bundles: ["CoreTests"]),
            )
            Issue.record("expected graph loading to fail")
        } catch let failure as ToolFailure {
            #expect(failure.description.contains("tuist graph failed"))
        }

        var isDirectory = ObjCBool(false)
        #expect(FileManager.default.fileExists(
            atPath: work.appending(path: "tuist-graph").path,
            isDirectory: &isDirectory,
        ))
        #expect(isDirectory.boolValue)
    }

    @Test func malformedBestEffortSnapshotReportDoesNotMaskPassingTests() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(standardOutput: """
            ◇ Suite ExampleTests started.
            ◇ Test works() started.
            SNAPSHOT_TIMING {"id":"missing-fields"}
            ✔ Test works() passed after 0.001 seconds.
            ** TEST SUCCEEDED **

            """),
        ])
        let terminal = MemoryTerminal()
        let service = TestService(
            runner: runner,
            simulator: StubSimulatorResolver(udid: "UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": root.appending(path: "work").path],
        )

        let status = try await service.run(
            makeTestRequest(scope: .all, build: false, generate: false, timings: true),
        )

        #expect(status == 0)
        #expect(await terminal.standardErrorText.contains(
            "warning: could not build snapshot detail report",
        ))
        #expect(await terminal.standardOutputText.contains("==> Passed."))
    }

    @Test func emptyWorkDirectoryOverrideFallsBackWithoutChmoddingTheRepository() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.path,
        )
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "base\n"),
            .stub(standardOutput: "abcdef\n"),
            .stub(),
            .stub(),
            .stub(),
        ])
        let service = TestService(
            runner: runner,
            simulator: StubSimulatorResolver(udid: "UNUSED"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: MemoryTerminal(),
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": ""],
        )

        _ = try await service.run(makeTestRequest(scope: .changed))

        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int,
        )
        #expect(permissions == 0o755)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains {
            $0.hasPrefix("where-test-")
        })
    }

    @Test func snapshotScopeForwardsTheCISettleMultiplier() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let testOutput = """
        ◇ Suite SnapshotTests started.
        ◇ Test image() started.
        ✔ Test image() passed after 0.001 seconds.
        ** TEST SUCCEEDED **

        """
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(standardOutput: testOutput),
        ])
        let service = TestService(
            runner: runner,
            simulator: StubSimulatorResolver(udid: "UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: MemoryTerminal(),
            repository: root,
            temporaryDirectory: root,
            environment: [
                "TEST_WORKDIR": root.appending(path: "work").path,
                "SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER": "2",
            ],
        )

        let status = try await service.run(
            makeTestRequest(scope: .snapshots, build: false, generate: false),
        )

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations[2].environment[
            "TEST_RUNNER_SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER",
        ] == "2")
    }
}

private func makeTestRequest(
    scope: TestScope,
    bundles: [String] = [],
    only: [String] = [],
    baseReference: String = "origin/main",
    build: Bool = true,
    generate: Bool = true,
    record: String? = nil,
    device: String = "iPhone 17",
    os: String = "27.0",
    sharedSimulator: Bool = false,
    timings: Bool = false,
    review: Bool = false,
    heartbeat: TimeInterval = 15,
    statusFile: String? = nil,
) -> TestRequest {
    TestRequest(
        scope: scope,
        bundles: bundles,
        only: only,
        baseReference: baseReference,
        build: build,
        generate: generate,
        record: record,
        device: device,
        os: os,
        sharedSimulator: sharedSimulator,
        timings: timings,
        review: review,
        heartbeat: heartbeat,
        statusFile: statusFile,
    )
}

private actor StubSimulatorResolver: SimulatorResolving {
    struct Call: Equatable {
        let device: String
        let os: String
        let shared: Bool
    }

    let udid: String
    private(set) var calls: [Call] = []

    init(udid: String) {
        self.udid = udid
    }

    func resolve(device: String, os: String, shared: Bool) -> String {
        calls.append(Call(device: device, os: os, shared: shared))
        return udid
    }
}
