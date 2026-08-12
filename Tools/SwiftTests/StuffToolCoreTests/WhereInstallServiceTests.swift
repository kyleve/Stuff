import Foundation
import StuffToolCore
import Testing

struct WhereInstallServiceTests {
    @Test func orchestratesSignedBuildExactDeviceInstallPromptAndLaunch() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "where-install", directoryHint: .isDirectory)
        let fileSystem = FoundationFileSystem()
        try prepareInstallOutputs(work: work, fileSystem: fileSystem)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "PATH=/usr/bin\nTUIST_DEVELOPMENT_TEAM=ABCDE12345\n"),
            .stub(),
            .stub(standardOutput: "build output\n"),
            .stub(),
            .stub(standardOutput: "install output\n"),
            .stub(standardOutput: "launch output\n"),
        ])
        let terminal = InteractiveInstallTerminal()
        let service = WhereInstallService(
            runner: runner,
            fileSystem: fileSystem,
            terminal: terminal,
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": work.path],
        )

        let status = try await service.run(
            makeWhereInstallRequest(
                device: "UDID-A",
                cloudKit: true,
                assumeYes: false,
            ),
        )

        #expect(status == 0)
        let invocations = await runner.invocations
        #expect(invocations.count == 6)
        #expect(invocations[0].arguments == [
            "exec",
            "--",
            "env",
        ])
        #expect(invocations[1].arguments == ["exec", "--", "tuist", "generate", "--no-open"])
        #expect(invocations[2].executable == "mise")
        #expect(invocations[2].arguments.contains("build"))
        #expect(invocations[2].arguments.contains("SWIFT_OPTIMIZATION_LEVEL=-O"))
        #expect(invocations[2].arguments.contains(
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) WHERE_CLOUDKIT_VALIDATION",
        ))
        #expect(invocations[3].arguments == [
            "devicectl",
            "list",
            "devices",
            "--json-output",
            work.appending(path: "devices.json").path,
        ])
        #expect(invocations[4].arguments.contains("DEVICE-A"))
        #expect(invocations[4].arguments.contains(
            work.appending(path: "DerivedData/Build/Products/Debug-iphoneos/Where.app").path,
        ))
        #expect(invocations[5].arguments.suffix(2) == ["--terminate-existing", "com.stuff.where"])
        #expect(await terminal.prompts == ["Press Enter to install, or Ctrl-C to cancel... "])
        #expect(await terminal.standardErrorText.contains("using: Kai's iPhone (DEVICE-A)"))
        #expect(await terminal.standardOutputText.contains("CloudKit validation enabled"))
    }

    @Test func dryRunPerformsNoIOOrExternalCommands() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "dry", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [])
        let terminal = MemoryTerminal()
        let service = WhereInstallService(
            runner: runner,
            fileSystem: FoundationFileSystem(),
            terminal: terminal,
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": work.path],
        )

        let status = try await service.run(
            makeWhereInstallRequest(
                device: "Phone",
                optimize: false,
                launch: false,
                dryRun: true,
            ),
        )

        #expect(status == 0)
        #expect(await runner.invocations.isEmpty)
        #expect(try FoundationFileSystem().kind(of: work) == .missing)
        #expect(await terminal.standardOutputText.contains("no project generation"))
        #expect(await terminal.standardOutputText.contains("launch disabled"))
    }

    @Test func missingTeamAndBuildFailureRemainNonzeroPrerequisites() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }

        let missingTeam = WhereInstallService(
            runner: FakeCommandRunner(responses: [.stub()]),
            fileSystem: FoundationFileSystem(),
            terminal: MemoryTerminal(),
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": root.appending(path: "missing").path],
        )
        do {
            _ = try await missingTeam.run(makeWhereInstallRequest())
            Issue.record("expected missing team failure")
        } catch let failure as ToolFailure {
            #expect(failure.description.contains("no Apple Developer team configured"))
        }

        let buildRunner = FakeCommandRunner(responses: [
            .stub(standardOutput: "TUIST_DEVELOPMENT_TEAM=TEAM\n"),
            .stub(),
            .stub(exitCode: 65),
        ])
        let buildFailure = WhereInstallService(
            runner: buildRunner,
            fileSystem: FoundationFileSystem(),
            terminal: MemoryTerminal(),
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": root.appending(path: "build").path],
        )
        do {
            _ = try await buildFailure.run(makeWhereInstallRequest())
            Issue.record("expected build failure")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(65))
        }
    }

    @Test func signingTeamLookupFailureSurfacesStderrAndStatus() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(exitCode: 78, standardError: "mise: malformed configuration\n"),
        ])
        let terminal = MemoryTerminal()
        let service = WhereInstallService(
            runner: runner,
            fileSystem: FoundationFileSystem(),
            terminal: terminal,
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": root.appending(path: "failed").path],
        )

        do {
            _ = try await service.run(makeWhereInstallRequest())
            Issue.record("expected signing-team lookup failure")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(78))
        }

        #expect(await terminal.standardErrorText == "mise: malformed configuration\n")
        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.arguments == [
            "exec",
            "--",
            "env",
        ])
    }

    @Test func confirmationEOFStopsBeforeDeviceInstallation() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let work = root.appending(path: "where-install", directoryHint: .isDirectory)
        let fileSystem = FoundationFileSystem()
        try prepareInstallOutputs(work: work, fileSystem: fileSystem)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "TUIST_DEVELOPMENT_TEAM=ABCDE12345\n"),
            .stub(),
            .stub(),
            .stub(),
        ])
        let terminal = InteractiveInstallTerminal(response: nil)
        let service = WhereInstallService(
            runner: runner,
            fileSystem: fileSystem,
            terminal: terminal,
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": work.path],
        )

        do {
            _ = try await service.run(
                makeWhereInstallRequest(device: "UDID-A", launch: false),
            )
            Issue.record("expected EOF to cancel installation")
        } catch let failure as ToolFailure {
            #expect(failure == .exitCode(1))
        }

        #expect(await runner.invocations.count == 4)
        #expect(await terminal.prompts == ["Press Enter to install, or Ctrl-C to cancel... "])
    }
}

private func makeWhereInstallRequest(
    device: String? = nil,
    configuration: String = "Debug",
    optimize: Bool = true,
    cloudKit: Bool = false,
    launch: Bool = true,
    assumeYes: Bool = false,
    dryRun: Bool = false,
) -> WhereInstallRequest {
    WhereInstallRequest(
        device: device,
        configuration: configuration,
        optimize: optimize,
        cloudKit: cloudKit,
        launch: launch,
        assumeYes: assumeYes,
        dryRun: dryRun,
    )
}

private func prepareInstallOutputs(
    work: URL,
    fileSystem: FoundationFileSystem,
) throws {
    try fileSystem.createDirectory(
        at: work.appending(
            path: "DerivedData/Build/Products/Debug-iphoneos/Where.app",
            directoryHint: .isDirectory,
        ),
        withIntermediateDirectories: true,
    )
    try fileSystem.write(
        fixtureData("devicectl-devices", extension: "json"),
        to: work.appending(path: "devices.json"),
        atomically: false,
    )
}

private actor InteractiveInstallTerminal: Terminal {
    private let response: String?
    private(set) var standardOutput: [UInt8] = []
    private(set) var standardError: [UInt8] = []
    private(set) var prompts: [String] = []

    init(response: String? = "") {
        self.response = response
    }

    func write(_ bytes: [UInt8], to stream: TerminalStream) {
        switch stream {
            case .standardOutput: standardOutput += bytes
            case .standardError: standardError += bytes
        }
    }

    func isInteractive() -> Bool {
        true
    }

    func isInputInteractive() -> Bool {
        true
    }

    func readLine(prompt: String) -> String? {
        prompts.append(prompt)
        return response
    }

    var standardOutputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
    }
}
