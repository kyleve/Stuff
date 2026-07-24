import ArgumentParser
import Foundation
import PortholeCore

/// `porthole connectors` — list the connectors a paired app exposes.
struct ConnectorsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connectors",
        abstract: "List the app's connectors.",
    )

    @OptionGroup var appOption: AppOption

    func run() async throws {
        let manifests = try await CLIRuntime.withSession(appOption.app) { try await $0.manifest() }
        let rows = manifests.map { manifest in
            PortholeValue.object([
                "id": .string(manifest.connector.id.rawValue),
                "title": .string(manifest.connector.title),
                "actions": .int(Int64(manifest.actions.count)),
                "sources": .int(Int64(manifest.dataSources.count)),
                "summary": .string(manifest.connector.summary),
            ])
        }
        print(OutputFormatting.table(rows))
    }
}

/// `porthole actions [connector]` — list actions, with parameter schemas.
struct ActionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "actions",
        abstract: "List actions and their parameters.",
    )

    @OptionGroup var appOption: AppOption

    @Argument(help: "Only actions for this connector id.")
    var connector: String?

    func run() async throws {
        let manifests = try await CLIRuntime.withSession(appOption.app) { try await $0.manifest() }
        for manifest in manifests
            where connector == nil || manifest.connector.id.rawValue == connector
        {
            for action in manifest.actions {
                let destructive = action.isDestructive ? " [destructive]" : ""
                print("\(manifest.connector.id)/\(action.id)\(destructive) — \(action.summary)")
                print("  parameters: \(OutputFormatting.json(action.parameters.jsonSchema()))")
            }
        }
    }
}

/// `porthole sources [connector]` — list data sources, with row/filter schemas.
struct SourcesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "List data sources and their filters.",
    )

    @OptionGroup var appOption: AppOption

    @Argument(help: "Only sources for this connector id.")
    var connector: String?

    func run() async throws {
        let manifests = try await CLIRuntime.withSession(appOption.app) { try await $0.manifest() }
        for manifest in manifests
            where connector == nil || manifest.connector.id.rawValue == connector
        {
            for source in manifest.dataSources {
                let live = source.supportsSubscription ? " [subscribable]" : ""
                print("\(manifest.connector.id)/\(source.id)\(live) — \(source.summary)")
                print("  filters: \(OutputFormatting.json(source.filters.jsonSchema()))")
            }
        }
    }
}
