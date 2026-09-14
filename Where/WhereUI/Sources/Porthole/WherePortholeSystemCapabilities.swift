import CryptoKit
import Foundation
import PeriscopeCore
import PortholeRuntime
import UIKit
import WhereCore

/// Platform inspection uses the active process and its already-open log store.
enum WherePortholeSystemCapabilities {
    @MainActor
    static func install(
        scope: WhereScope?,
        registry: PortholeRegistry,
        token: PortholeScopeToken,
        screenshot: @escaping @MainActor @Sendable () throws -> Data,
    ) async throws {
        try await registry.register(
            capability(
                "where.system",
                parameters: [],
                summary: "Current process lifecycle and installed build identity",
            ),
            in: token,
        ) { _, registry in
            let files = try await registry.sourceFiles(in: token)
            let identity = files.sorted { $0.path < $1.path }
                .map { "\($0.path)\u{0}\($0.sha256)" }.joined(separator: "\n")
            let sourceHash = SHA256.hash(data: Data(identity.utf8))
                .map { String(format: "%02x", $0) }.joined()
            return await MainActor.run {
                let bundle = Bundle.main
                return .object([
                    "applicationState": .integer(Int64(UIApplication.shared.applicationState
                            .rawValue)),
                    "lowPowerMode": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled),
                    "thermalState": .integer(Int64(ProcessInfo.processInfo.thermalState.rawValue)),
                    "gitSHA": .string(bundle
                        .object(forInfoDictionaryKey: "WhereGitSHA") as? String ?? "unknown"),
                    "gitStatus": .string(bundle
                        .object(forInfoDictionaryKey: "WhereGitStatus") as? String ?? "unknown"),
                    "configuration": .string(bundle
                        .object(forInfoDictionaryKey: "WhereConfiguration") as? String ??
                        "unknown"),
                    "optimization": .string(bundle
                        .object(forInfoDictionaryKey: "WhereSwiftOptimizationLevel") as? String ??
                        "unknown"),
                    "compilationMode": .string(bundle
                        .object(forInfoDictionaryKey: "WhereSwiftCompilationMode") as? String ??
                        "unknown"),
                    "compiler": .string(bundle
                        .object(forInfoDictionaryKey: "WhereSwiftCompilerVersion") as? String ??
                        "unknown"),
                    "sourceArchiveSHA256": .string(sourceHash),
                    "sourceFileCount": .integer(Int64(files.count)),
                ])
            }
        }
        try await registry.register(
            capability(
                "where.screenshot",
                parameters: [],
                summary: "Read the frozen application image. Live capture is available only while Porthole is hidden.",
            ),
            in: token,
        ) { _, _ in
            let data = try await screenshot()
            return .object([
                "mimeType": .string("image/png"),
                "base64": .string(data.base64EncodedString()),
            ])
        }
        guard let scope else { return }
        let parameters: [PortholeParameter] = [
            .init(
                name: "contains",
                summary: "Message search; empty matches all",
                schema: .string,
                required: true,
            ),
            .init(
                name: "externalID",
                summary: "Entity store URL, or null",
                schema: .optional(.string),
                required: true,
            ),
            .init(
                name: "afterSequence",
                summary: "Fixed lower insertion watermark, or null. Advance only after consuming every page.",
                schema: .optional(.integer),
                required: true,
            ),
            .init(
                name: "throughSequence",
                summary: "Upper watermark returned by the first page; null captures the current store watermark.",
                schema: .optional(.integer),
                required: true,
            ),
            .init(
                name: "offset",
                summary: "Newest-first page offset, starting at zero",
                schema: .integer,
                required: true,
            ),
            .init(name: "limit", summary: "Page size, 1...200", schema: .integer, required: true),
        ]
        try await registry.register(
            capability(
                "where.logs.query",
                parameters: parameters,
                summary: "Read stored log evidence. Absence does not prove a branch did not execute.",
            ),
            in: token,
        ) { invocation, _ in
            guard let store = await scope.logStore
            else { throw PortholeError.unsupported("The current scope has no ready log store") }
            return try await queryLogs(store: store, arguments: invocation.arguments)
        }
    }

    static func queryLogs(
        store: PeriscopeStore,
        arguments: PortholeValue,
    ) async throws -> PortholeValue {
        guard case let .integer(limit) = arguments["limit"],
              (1 ... 200).contains(limit),
              case let .integer(offset) = arguments["offset"],
              (0 ... Int64(Int.max - 201)).contains(offset)
        else {
            throw PortholeError
                .invalidArguments(
                    "limit must be 1...200 and offset must be nonnegative and leave room for one page",
                )
        }
        var query = LogQuery()
        query.messageContains = arguments["contains"]?.stringValue
        query.externalID = arguments["externalID"]?.stringValue
        if case let .integer(sequence) = arguments["afterSequence"] {
            query.afterSequence = Int(sequence)
        }
        let watermark: Int = if case let .integer(sequence) = arguments["throughSequence"] {
            Int(sequence)
        } else {
            try await store.latestSequence() ?? -1
        }
        query.throughSequence = watermark
        query.limit = Int(limit) + 1
        query.offset = Int(offset)
        let events = try await store.events(matching: query)
        var rows: [PortholeValue] = []
        for event in events.prefix(Int(limit)) {
            try rows.append(.object([
                "id": .string(event.id.uuidString),
                "sequence": .integer(Int64(event.sequence)),
                "date": .encoding(event.date),
                "event": .string(event.eventName),
                "message": .string(event.message),
                "scopes": .encoding(event.scopes),
                "payload": .parse(event.payload),
                "level": .encoding(event.level),
                "tags": .encoding(event.tags),
                "externalID": .encoding(event.externalID),
                "callSite": .encoding(event.callSite),
                "sessionID": .encoding(event.sessionID),
                "attachments": .array(event.attachments.map { .object([
                    "name": .string($0.name),
                    "contentType": .string($0.contentType.mimeType),
                ]) }),
            ]))
        }
        return .object([
            "events": .array(rows),
            "throughSequence": .integer(Int64(watermark)),
            "nextOffset": events.count > Int(limit) ? .integer(offset + limit) : .null,
            "ordering": .string("Event date descending, then insertion sequence descending"),
            "paging": .string(
                "Keep all filters and throughSequence fixed while following nextOffset. Later appends are excluded; concurrent pruning can remove evidence.",
            ),
        ])
    }

    private static func capability(
        _ name: String,
        parameters: [PortholeParameter],
        summary: String,
    ) -> PortholeCapability {
        .init(
            id: .init(rawValue: name),
            module: .init(rawValue: "WhereUI"),
            name: name,
            summary: summary,
            parameters: parameters,
            result: .any,
            effect: .read,
            source: .init(
                path: "Where/WhereUI/Sources/Porthole/WherePortholeSystemCapabilities.swift",
                line: 1,
            ),
            ownership: .adapter,
            availability: .callable,
        )
    }
}
