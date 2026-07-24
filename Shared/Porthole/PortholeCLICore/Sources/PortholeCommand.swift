import ArgumentParser
import Foundation
import PortholeClientKit
import PortholeCore

/// `porthole` — the command-line surface for talking to paired device apps.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct PortholeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "porthole",
        abstract: "Access data and actions in a running iOS app over the local network.",
        subcommands: [
            DevicesCommand.self,
            PairCommand.self,
            UnpairCommand.self,
            ConnectorsCommand.self,
            ActionsCommand.self,
            SourcesCommand.self,
            CallCommand.self,
            QueryCommand.self,
            TailCommand.self,
            MCPCommand.self,
        ],
    )

    public init() {}
}

/// The shared `--app` selector for subcommands that target one paired app.
struct AppOption: ParsableArguments {
    @Option(
        name: .long,
        help: "Which paired app (bundle id, or an app/device name substring). Optional when exactly one app is paired.",
    )
    var app: String?
}

enum CLIRuntime {
    static func makeClient() -> PortholeClient {
        PortholeClient()
    }

    static func resolveApp(_ selector: String?) throws -> PairedApp {
        try AppResolution.resolve(selector: selector, from: makeClient().pairedApps())
    }

    /// Resolves the app, opens a session, runs `body`, and always closes.
    static func withSession<T>(
        _ selector: String?,
        _ body: (PortholeSession) async throws -> T,
    ) async throws -> T {
        let paired = try resolveApp(selector)
        let session = try await makeClient().connect(to: paired)
        do {
            let result = try await body(session)
            await session.close()
            return result
        } catch {
            await session.close()
            throw error
        }
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
