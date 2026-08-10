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
            .stub(standardOutput: "ABCDE12345\n"),
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
            WhereInstallRequest(
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
            "printenv",
            "TUIST_DEVELOPMENT_TEAM",
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
            WhereInstallRequest(
                device: "Phone",
                optimize: false,
                launch: false,
                dryRun: true,
            ),
        )

        #expect(status == 0)
        #expect(await runner.invocations.isEmpty)
        #expect(FoundationFileSystem().kind(of: work) == .missing)
        #expect(await terminal.standardOutputText.contains("no project generation"))
        #expect(await terminal.standardOutputText.contains("launch disabled"))
    }

    @Test func missingTeamAndBuildFailureRemainNonzeroPrerequisites() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }

        let missingTeam = WhereInstallService(
            runner: FakeCommandRunner(responses: [.stub(exitCode: 1)]),
            fileSystem: FoundationFileSystem(),
            terminal: MemoryTerminal(),
            repository: root,
            home: root,
            environment: ["WHERE_INSTALL_WORKDIR": root.appending(path: "missing").path],
        )
        do {
            _ = try await missingTeam.run(WhereInstallRequest())
            Issue.record("expected missing team failure")
        } catch let failure as WhereInstallFailure {
            #expect(failure.description.contains("no Apple Developer team configured"))
        }

        let buildRunner = FakeCommandRunner(responses: [
            .stub(standardOutput: "TEAM"),
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
            _ = try await buildFailure.run(WhereInstallRequest())
            Issue.record("expected build failure")
        } catch let failure as WhereInstallFailure {
            #expect(failure == .exitCode(65))
        }
    }
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
    private(set) var standardOutput: [UInt8] = []
    private(set) var standardError: [UInt8] = []
    private(set) var prompts: [String] = []

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
        return ""
    }

    var standardOutputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
    }
}
