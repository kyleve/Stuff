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
            .stub(),
            .stub(),
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

        let status = try await service.run(makeTestRequest(
            scope: .changed,
            architectureMode: .run,
        ))

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 9)
        #expect(invocations.prefix(3).allSatisfy { $0.executable == "swift" })
        #expect(invocations[3].executable == "mise")
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
        #expect(invocations.count == 2)
        #expect(invocations.contains { $0.executable == "mise" } == false)
        #expect(invocations[1].environment[
            "TEST_RUNNER_SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER",
        ] == "2")
    }

    @Test func architectureOnlyStopsBeforeBackupFilesystemAndSimulatorWork() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [.stub(), .stub(), .stub()])
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

        let status = try await service.run(makeTestRequest(
            scope: .changed,
            architectureMode: .only,
        ))

        #expect(status == 0)
        #expect(await runner.invocations.count == 3)
        #expect(await simulator.calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "work").path) == false)
        #expect(await terminal.standardOutputText.contains("Testing backup upgrader") == false)
    }

    @Test func buildArtifactsBuildsBothSchemesOnceWithoutBootingOrTesting() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let artifacts = root.appending(path: "artifacts", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(),
            .stub(standardOutput: "manifest created\n"),
            .stub(standardOutput: "321\tproducts\n"),
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

        let status = try await service.run(makeTestRequest(
            scope: .everything,
            artifactMode: .build(directory: artifacts.path),
            generate: false,
        ))

        #expect(status == 0)
        #expect(await simulator.calls.isEmpty)
        let invocations = await runner.invocations
        #expect(invocations.count == 4)
        #expect(invocations[0].arguments == [
            "build-for-testing",
            "-workspace",
            "Stuff.xcworkspace",
            "-scheme",
            "Stuff-iOS-Tests",
            "-configuration",
            "Debug",
            "-destination",
            "generic/platform=iOS Simulator",
            "-derivedDataPath",
            artifacts.appending(path: "DerivedData").path,
            "ARCHS=arm64",
            "ONLY_ACTIVE_ARCH=YES",
        ])
        #expect(invocations[1].arguments.contains("StuffSnapshotTests"))
        #expect(invocations[2].arguments == [
            ".circleci/test_artifacts.py",
            "create",
            "--root",
            artifacts.path,
            "--scheme",
            "Stuff-iOS-Tests",
            "--scheme",
            "StuffSnapshotTests",
        ])
        #expect(await terminal.standardOutputText.contains(
            "CI_ARTIFACT {\"bytes\":328704,\"schemes\":2}",
        ))
    }

    @Test func artifactsUseValidatedXctestrunAndProductPaths() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let artifacts = root.appending(path: "artifacts", directoryHint: .isDirectory)
        let testOutput = """
        ◇ Suite ExampleTests started.
        ◇ Test works() started.
        ✔ Test works() passed after 0.001 seconds.
        ** TEST SUCCEEDED **

        """
        let paths = """
        {"products":"/artifacts/Products","schemes":{"Stuff-iOS-Tests":"/artifacts/tests.xctestrun"}}
        """
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: paths),
            .stub(standardOutput: testOutput),
        ])
        let terminal = MemoryTerminal()
        let service = TestService(
            runner: runner,
            simulator: StubSimulatorResolver(udid: "ARTIFACT-UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["TEST_WORKDIR": root.appending(path: "work").path],
        )

        let status = try await service.run(makeTestRequest(
            scope: .all,
            artifactMode: .test(directory: artifacts.path, enumerateSuites: nil),
            build: false,
            generate: false,
        ))

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 2)
        #expect(invocations[1].arguments.starts(with: [
            "test-without-building",
            "-xctestrun",
            "/artifacts/tests.xctestrun",
            "-destination",
            "platform=iOS Simulator,id=ARTIFACT-UDID",
        ]))
        #expect(invocations[1].environment[
            "TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH",
        ] == "/artifacts/Products")
        #expect(await terminal.standardOutputText.contains(
            "Validated test artifacts before simulator boot.",
        ))
    }

    @Test func onlyFileFiltersArtifactSnapshotsWithoutLoadingTheRepositoryGraph() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let shard = root.appending(path: "shard.txt")
        try Data("WhereUISnapshotTests/SettingsTests\n".utf8).write(to: shard)
        let paths = """
        {"products":"/artifacts/Products","schemes":{"StuffSnapshotTests":"/artifacts/snapshots.xctestrun"}}
        """
        let testOutput = """
        ◇ Suite SettingsTests started.
        ◇ Test image() started.
        ✔ Test image() passed after 0.001 seconds.
        ** TEST SUCCEEDED **

        """
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: paths),
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
            environment: ["TEST_WORKDIR": root.appending(path: "work").path],
        )

        let status = try await service.run(makeTestRequest(
            scope: .snapshots,
            onlyFile: shard.path,
            artifactMode: .test(directory: "/artifacts", enumerateSuites: nil),
            build: false,
            generate: false,
        ))

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 2)
        #expect(invocations[1].arguments.suffix(2) == ["-only-testing", "@\(shard.path)"])
    }

    @Test func enumerationWritesSuitesAndStopsBeforeTheTestReporter() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let enumeration = root.appending(path: "suites.txt")
        let paths = """
        {"products":"/artifacts/Products","schemes":{"StuffSnapshotTests":"/artifacts/snapshots.xctestrun"}}
        """
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: paths),
            .stub(),
            .stub(standardOutput: "Wrote 45 suites\n"),
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

        let status = try await service.run(makeTestRequest(
            scope: .snapshots,
            artifactMode: .test(
                directory: "/artifacts",
                enumerateSuites: enumeration.path,
            ),
            build: false,
            generate: false,
        ))

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 3)
        #expect(invocations[1].arguments.contains("-enumerate-tests"))
        #expect(invocations[2].arguments == [
            ".circleci/test_artifacts.py",
            "suites",
            "--input",
            root.appending(path: "work/StuffSnapshotTests-enumeration.json").path,
            "--output",
            enumeration.path,
        ])
        #expect(await terminal.standardOutputText.contains("==> Testing") == false)
    }

    @Test func failedBuildEmitsTimingAndPreservesTheChildStatus() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(exitCode: 23, standardError: "build failed\n"),
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

        do {
            _ = try await service.run(makeTestRequest(
                scope: .snapshots,
                generate: false,
            ))
            Issue.record("expected build failure")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(23))
        }
        #expect(await terminal.standardOutputText.contains("\"phase\":\"build\""))
        #expect(await terminal.standardOutputText.contains("\"status\":23"))
        #expect(await terminal.standardErrorText.contains("build failed"))
    }
}

private func makeTestRequest(
    scope: TestScope,
    bundles: [String] = [],
    only: [String] = [],
    onlyFile: String? = nil,
    baseReference: String = "origin/main",
    architectureMode: TestArchitectureMode = .skip,
    artifactMode: TestArtifactMode = .local,
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
        onlyFile: onlyFile,
        baseReference: baseReference,
        architectureMode: architectureMode,
        artifactMode: artifactMode,
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
