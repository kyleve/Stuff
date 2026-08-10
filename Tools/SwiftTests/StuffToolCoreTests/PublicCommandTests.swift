import StuffToolCore
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

    @Test func privateSelectorsResolveEveryPublicCommand() {
        for command in PublicCommand.allCases {
            #expect(PublicCommand(rawValue: command.rawValue) == command)
            #expect(command.commandType.configuration.commandName == command.publicPath)
        }
    }
}
