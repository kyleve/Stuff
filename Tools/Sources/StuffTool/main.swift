import ArgumentParser
import StuffToolCore

@main
struct StuffTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stuff",
        abstract: "Run Stuff's repository developer tools.",
        subcommands: [
            SimulatorCommand.self,
            TestCommand.self,
            XCStringsCommand.self,
        ],
    )
}
