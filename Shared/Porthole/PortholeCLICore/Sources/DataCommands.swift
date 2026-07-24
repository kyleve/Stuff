import ArgumentParser
import Foundation
import PortholeClientKit
import PortholeCore

/// `porthole call <connector>/<action>` — invoke an action.
struct CallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "call",
        abstract: "Invoke an action.",
    )

    @OptionGroup var appOption: AppOption

    @Argument(help: "The action, as connector/action.")
    var ref: String

    @Option(name: .customLong("param"), help: "A parameter, as key=value (repeatable).")
    var params: [String] = []

    @Option(name: .long, help: "The full parameters object as JSON.")
    var json: String?

    @Flag(name: .long, help: "Skip the confirmation prompt for destructive actions.")
    var yes = false

    @Option(
        name: .long,
        help: "Write a returned data value to this file instead of printing base64.",
    )
    var out: String?

    func run() async throws {
        let parsed = try CLIValueParsing.parseRef(ref)
        let parameters = try CLIValueParsing.buildParameters(json: json, params: params)

        let result = try await CLIRuntime.withSession(appOption.app) { session -> PortholeValue in
            if !yes {
                let manifests = try await session.manifest()
                if isDestructive(parsed, in: manifests) {
                    FileHandle.standardError
                        .write(Data("Action `\(ref)` is destructive. Continue? [y/N] ".utf8))
                    let answer = readLine(strippingNewline: true)?.lowercased()
                    guard answer == "y" || answer == "yes" else {
                        throw CleanExit.message("Cancelled.")
                    }
                }
            }
            return try await session.invoke(parsed.actionRef, parameters: parameters)
        }

        if let out, let data = extractData(result) {
            try data.write(to: URL(fileURLWithPath: out))
            print("Wrote \(data.count) bytes to \(out).")
        } else {
            print(OutputFormatting.json(result))
        }
    }

    private func isDestructive(_ ref: ParsedRef, in manifests: [ConnectorManifest]) -> Bool {
        manifests
            .first { $0.connector.id.rawValue == ref.connector }?
            .actions.first { $0.id.rawValue == ref.member }?
            .isDestructive ?? false
    }

    private func extractData(_ value: PortholeValue) -> Data? {
        if case let .data(data) = value { return data }
        if case let .object(object) = value {
            for member in object.values {
                if case let .data(data) = member { return data }
            }
        }
        return nil
    }
}

/// `porthole query <connector>/<source>` — page through a data source.
struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query a data source.",
    )

    @OptionGroup var appOption: AppOption

    @Argument(help: "The source, as connector/source.")
    var ref: String

    @Option(name: .customLong("filter"), help: "A filter, as key=value (repeatable).")
    var filters: [String] = []

    @Option(name: .long, help: "Maximum rows per page.")
    var limit: Int?

    @Option(name: .long, help: "Opaque cursor from a previous page.")
    var cursor: String?

    @Flag(name: .long, help: "Follow nextCursor and return all rows.")
    var all = false

    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .table

    enum OutputFormat: String, ExpressibleByArgument { case table, json }

    func run() async throws {
        let parsed = try CLIValueParsing.parseRef(ref)
        let filterValue = try CLIValueParsing.buildParameters(json: nil, params: filters)

        let rows = try await CLIRuntime.withSession(appOption.app) { session -> [PortholeValue] in
            var collected: [PortholeValue] = []
            var nextCursor = cursor
            repeat {
                let page = try await session.query(
                    parsed.dataSourceRef,
                    PortholeQuery(filters: filterValue, limit: limit, cursor: nextCursor),
                )
                collected.append(contentsOf: page.rows)
                nextCursor = page.nextCursor
            } while all && nextCursor != nil
            return collected
        }

        switch format {
            case .table: print(OutputFormatting.table(rows))
            case .json: print(OutputFormatting.json(.array(rows)))
        }
    }
}

/// `porthole tail <connector>/<source>` — stream a subscribable source.
struct TailCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tail",
        abstract: "Stream a subscribable data source until interrupted.",
    )

    @OptionGroup var appOption: AppOption

    @Argument(help: "The source, as connector/source.")
    var ref: String

    @Option(name: .customLong("filter"), help: "A filter, as key=value (repeatable).")
    var filters: [String] = []

    func run() async throws {
        let parsed = try CLIValueParsing.parseRef(ref)
        _ = try CLIValueParsing.buildParameters(json: nil, params: filters)

        try await CLIRuntime.withSession(appOption.app) { session in
            let stream = try await session.subscribe(parsed.dataSourceRef)
            for try await value in stream {
                print(OutputFormatting.json(value))
            }
        }
    }
}
