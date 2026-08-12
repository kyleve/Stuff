import Foundation
import StuffToolCore
import Testing

struct ProfileServiceTests {
    @Test func sOnlyRunBuildsTestsAndReportsTypedXCResultData() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "profile", directoryHint: .isDirectory)
        let fixture = try fixtureData("xcresult-tests", extension: "json")
        let runner = FakeCommandRunner(responses: [
            .stub(standardError: "generation warning\n"),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            .stub(standardOutput: "xcode test log\n"),
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(fixture),
                standardError: [],
            ),
        ])
        let simulator = StubProfileSimulator(udid: "PROFILE-UDID")
        let terminal = MemoryTerminal()
        let service = ProfileService(
            runner: runner,
            simulator: simulator,
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["PROFILE_WORKDIR": work.path],
        )

        let status = try await service.run(
            request(scope: .tests, snapshots: false),
        )

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 4)
        #expect(invocations[0].arguments == [
            "exec",
            "--",
            "tuist",
            "generate",
            "--no-open",
        ])
        #expect(invocations[1].arguments.contains("-showBuildSettings"))
        #expect(invocations[2].arguments == [
            "test",
            "-workspace",
            "Stuff.xcworkspace",
            "-scheme",
            "Stuff-iOS-Tests",
            "-destination",
            "platform=iOS Simulator,id=PROFILE-UDID",
            "-derivedDataPath",
            work.appending(path: "DerivedData").path,
            "-resultBundlePath",
            work.appending(path: "tests.xcresult").path,
            "-collect-test-diagnostics",
            "never",
        ])
        #expect(invocations[2].environment == [
            "TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH": "/tmp/Products",
        ])
        #expect(invocations[2].output == .merged)
        #expect(invocations[3].arguments.first == "xcresulttool")
        #expect(await terminal.standardOutputText.contains("TEST HOT SPOTS"))
        #expect(await terminal.standardOutputText.contains("2 tests, summed self-time 0.25s"))
        #expect(await terminal.standardErrorText.contains("generation warning"))
        #expect(try Data(contentsOf: work.appending(path: "tests.json")) == fixture)
    }

    @Test func buildOnlyPrintsTheParsedBuildTimingReport() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "profile", directoryHint: .isDirectory)
        let buildLog = try fixtureData("profile-build", extension: "log")
        let runner = FakeCommandRunner(responses: [
            .stub(),
            .stub(standardOutput: "    BUILT_PRODUCTS_DIR = /tmp/Products\n"),
            CommandResult(
                terminationStatus: .exited(0),
                standardOutput: Array(buildLog),
                standardError: [],
            ),
        ])
        let terminal = MemoryTerminal()
        let service = ProfileService(
            runner: runner,
            simulator: StubProfileSimulator(udid: "UDID"),
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            temporaryDirectory: root,
            environment: ["PROFILE_WORKDIR": work.path],
        )

        let status = try await service.run(request(scope: .build))

        #expect(status == 0)
        #expect(await terminal.standardOutputText.contains("BUILD HOT SPOTS"))
        #expect(await terminal.standardOutputText.contains("CompileSwiftSources"))
        #expect(await terminal.standardOutputText.contains("240ms"))
    }

    private func request(
        scope: ProfileScope,
        snapshots: Bool = true,
    ) -> ProfileRequest {
        ProfileRequest(
            scope: scope,
            snapshots: snapshots,
            ciShape: false,
            device: "iPhone 17",
            os: "27.0",
            top: 15,
            testThreshold: 0.1,
            typeCheckThreshold: 100,
        )
    }
}

private actor StubProfileSimulator: SimulatorResolving {
    let udid: String

    init(udid: String) {
        self.udid = udid
    }

    func resolve(device _: String, os _: String, shared _: Bool) -> String {
        udid
    }
}
