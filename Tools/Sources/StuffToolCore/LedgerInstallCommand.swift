import ArgumentParser

public struct LedgerInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./Ledger/install",
        abstract: "Build Ledger in Release and install it to /Applications.",
        discussion: """
        Produces an ad-hoc-signed standalone app, safely stops only the installed
        executable, replaces it through a rollback transaction, and launches it.
        """,
    )

    @Flag(name: .customLong("no-open"), help: "Install without launching Ledger.")
    var noOpen = false

    @Flag(help: "Describe the build and replacement without changing anything.")
    var dryRun = false

    public init() {}

    public func makeRequest() -> LedgerInstallRequest {
        LedgerInstallRequest(openAfterInstall: noOpen == false, dryRun: dryRun)
    }

    public mutating func run() async throws {
        let runtime = ToolRuntime()
        let status = try await performPublicCommand(terminal: runtime.terminal) {
            try await runtime.ledgerInstallService().run(makeRequest())
        }
        if status != 0 { throw ExitCode(status) }
    }
}
