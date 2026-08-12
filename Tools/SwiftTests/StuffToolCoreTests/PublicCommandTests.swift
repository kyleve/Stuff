import Foundation
import StuffToolCore
import Subprocess
import Testing

struct PublicCommandTests {
    @Test(arguments: PublicCommand.allCases)
    func helpNamesThePublicShim(command: PublicCommand) throws {
        do {
            var parsed = try command.commandType.parseAsRoot(["--help"])
            try parsed.run()
            Issue.record("expected help to request a clean exit")
        } catch {
            let termination = command.termination(for: error)

            #expect(termination.exitCode == 0)
            #expect(termination.stream == .standardOutput)
            #expect(termination.message.contains("USAGE: \(command.publicPath)"))
            #expect(termination.message.contains("stuff ") == false)
        }
    }

    @Test(arguments: PublicCommand.allCases)
    func invalidUsageKeepsTheLegacyStatus(command: PublicCommand) throws {
        do {
            _ = try command.commandType.parseAsRoot(["--not-a-real-option"])
            Issue.record("expected an unknown-option failure")
        } catch {
            let termination = command.termination(for: error)

            #expect(termination.exitCode == command.usageExitCode)
            #expect(termination.stream == .standardError)
            #expect(termination.message.contains("Usage: \(command.publicPath)"))
            #expect(termination.message.contains("\(command.publicPath) --help"))
        }
    }

    @Test func missingOptionValueUsesTheSameUsagePolicy() throws {
        do {
            _ = try PublicCommand.test.commandType.parseAsRoot(["--device"])
            Issue.record("expected a missing-value failure")
        } catch {
            let termination = PublicCommand.test.termination(for: error)

            #expect(termination.exitCode == 1)
            #expect(termination.message.contains("Missing value for '--device <device>'"))
            #expect(termination.message.contains("Usage: ./test"))
        }
    }

    @Test func iconsWithoutArgumentsPrintsFullUsageAndFails() throws {
        let termination = try #require(PublicCommand.icons.noArgumentTermination)

        #expect(termination.exitCode == 1)
        #expect(termination.stream == .standardOutput)
        #expect(termination.message.contains("USAGE: ./icons"))
        #expect(termination.message.contains("--add"))
        #expect(termination.message.contains("--remove"))
        #expect(termination.message.contains("--list"))
    }

    @Test func iconsWithoutArgumentsUsesTheLegacyPublicStreams() async throws {
        let result = try await Subprocess.run(
            .path(.init(prebuiltStuffExecutable.path)),
            arguments: ["icons"],
            output: .string(limit: .max),
            error: .string(limit: .max),
        )

        #expect(result.terminationStatus == .exited(1))
        #expect(result.standardOutput.contains("USAGE: ./icons"))
        #expect(result.standardError.isEmpty)
    }

    @Test func missingAndNonExecutableToolsKeepShellStatuses() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let missing = try await whereInstallLaunchStatus(path: directory.path)
        #expect(missing == .exited(127))

        let mise = directory.appending(path: "mise")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: mise)
        let nonExecutable = try await whereInstallLaunchStatus(path: directory.path)
        #expect(nonExecutable == .exited(126))
    }

    @Test func whereInstallHonorsTheLaunchHomeDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let home = directory.appending(path: "isolated-home", directoryHint: .isDirectory)

        let result = try await Subprocess.run(
            .path(.init(prebuiltStuffExecutable.path)),
            arguments: ["where-install", "--dry-run", "--no-launch"],
            environment: .inherit.updating([
                "HOME": home.path,
                "STUFF_REPOSITORY_ROOT": testRepositoryRoot.path,
            ]),
            workingDirectory: .init(testRepositoryRoot.path),
            output: .string(limit: .max),
            error: .string(limit: .max),
        )

        #expect(result.terminationStatus == .exited(0))
        #expect(result.standardOutput.contains(
            home.appending(path: "Library/Developer/Xcode/DerivedData").path,
        ))
        #expect(result.standardError.isEmpty)
    }

    @Test func privateSelectorsResolveEveryPublicCommand() {
        for command in PublicCommand.allCases {
            #expect(PublicCommand(rawValue: command.rawValue) == command)
            #expect(command.commandType.configuration.commandName == command.publicPath)
        }
    }
}

private func whereInstallLaunchStatus(
    path: String,
) async throws -> TerminationStatus {
    let result = try await Subprocess.run(
        .path(.init(prebuiltStuffExecutable.path)),
        arguments: ["where-install", "--yes"],
        environment: .inherit.updating([
            "PATH": path,
            "STUFF_REPOSITORY_ROOT": testRepositoryRoot.path,
        ]),
        workingDirectory: .init(testRepositoryRoot.path),
        output: .string(limit: .max),
        error: .discarded,
    )
    return result.terminationStatus
}
