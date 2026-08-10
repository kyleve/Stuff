import ArgumentParser
import StuffToolCore

@main
struct StuffTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stuff",
        abstract: "Run Stuff's repository developer tools.",
        subcommands: [
            FlakyCommand.self,
            IconsCommand.self,
            ProfileCommand.self,
            SimulatorCommand.self,
            TestCommand.self,
            XCStringsCommand.self,
        ],
    )
}
