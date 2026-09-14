import Foundation
import PortholeCore

/// The same bounded discovery and evidence queries serve the UI, agents, and remote clients.
public enum PortholeBuiltinCapabilities {
    public static func install(
        in registry: PortholeRegistry,
        scope: PortholeScopeToken,
    ) async throws {
        try await installObservations(in: registry, scope: scope)
        try await installCoverage(in: registry, scope: scope)
        try await add(
            "porthole.contexts",
            summary: "Captured screen origins and selected evidence",
            parameters: [],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            try await .encoding(registry.capturedContexts(in: invocation.scope))
        }
        try await add(
            "porthole.objects",
            summary: "Live typed handles owned by this scope",
            parameters: [],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            try await .encoding(registry.objectReferences(in: invocation.scope))
        }
        try await registry.register(
            PortholeCapability(
                id: .init(rawValue: "porthole.objects.release"),
                module: .init(rawValue: "PortholeRuntime"),
                name: "porthole.objects.release",
                summary: "Release a debugger handle and its derived children. Running native calls keep their arguments leased. This does not change application state.",
                parameters: [text("objectID"), text("typeName")],
                result: .any,
                effect: .isolated,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            ),
            in: scope,
        ) { invocation, registry in
            guard let objectID = try UUID(uuidString: string("objectID", invocation)) else {
                throw PortholeError.invalidArguments("objectID must be a UUID")
            }
            try await registry.release(PortholeObjectReference(
                id: objectID,
                scope: invocation.scope,
                typeName: string("typeName", invocation),
            ))
            return .null
        }
        try await add(
            "porthole.discover",
            summary: "Search capability names, signatures, and unsupported reasons. Results are paged.",
            parameters: [text("query"), integer("offset"), integer("limit")],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            let query = try string("query", invocation)
            let page = try bounds(invocation)
            let matches = try await registry.capabilities(in: invocation.scope).filter {
                let reason: String = switch $0.availability {
                    case let .unsupported(message): message
                    case .callable, .inspectable: ""
                }
                return query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.summary.localizedCaseInsensitiveContains(query) || $0.id.rawValue
                    .localizedCaseInsensitiveContains(query)
                    || reason.localizedCaseInsensitiveContains(query)
            }
            return try .object([
                "total": .integer(Int64(matches.count)),
                "items": .encoding(Array(matches.dropFirst(page.offset).prefix(page.limit))),
            ])
        }
        try await add(
            "porthole.source.search",
            summary: "Search the exact bundled source of this installed build; results contain source paths and line numbers.",
            parameters: [text("query"), integer("offset"), integer("limit")],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            let query = try string("query", invocation)
            guard !query.isEmpty
            else { throw PortholeError.invalidArguments("query must not be empty") }
            let page = try bounds(invocation)
            var hits: [PortholeValue] = []
            var count = 0
            for file in try await registry.sourceFiles(in: invocation.scope) {
                try Task.checkCancellation()
                for (index, line) in file.content.split(
                    separator: "\n",
                    omittingEmptySubsequences: false,
                ).enumerated()
                    where line.localizedCaseInsensitiveContains(query)
                {
                    if count >= page.offset, hits.count < page.limit {
                        try hits.append(.object([
                            "path": .string(file.path),
                            "line": .integer(Int64(index + 1)),
                            "text": .string(String(line)),
                            "sha256": .string(file.sha256),
                            "scope": .encoding(invocation.scope),
                        ]))
                    }
                    count += 1
                }
            }
            return .object(["total": .integer(Int64(count)), "items": .array(hits)])
        }
        try await add(
            "porthole.source.read",
            summary: "Read numbered lines from a bundled source file; offset is zero-based.",
            parameters: [text("path"), integer("offset"), integer("limit")],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            let path = try string("path", invocation)
            let page = try bounds(invocation)
            guard let file = try await registry.sourceFiles(in: invocation.scope)
                .first(where: { $0.path == path })
            else {
                throw PortholeError.invalidArguments("No bundled source at \(path)")
            }
            let lines = file.content.split(separator: "\n", omittingEmptySubsequences: false)
            return try .object([
                "path": .string(path),
                "firstLine": .integer(Int64(page.offset + 1)),
                "sha256": .string(file.sha256),
                "scope": .encoding(invocation.scope),
                "totalLines": .integer(Int64(lines.count)),
                "text": .string(lines.dropFirst(page.offset).prefix(page.limit)
                    .joined(separator: "\n")),
            ])
        }
    }

    private static func installCoverage(
        in registry: PortholeRegistry,
        scope: PortholeScopeToken,
    ) async throws {
        try await add(
            PortholeCoverageCapabilities.modules.rawValue,
            summary: "List all installed source coverage modules, including modules with no active declarations. Counts reflect compiled registrations in this scope. offset is nonnegative; limit is 1...200.",
            parameters: [integer("offset"), integer("limit")],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            let page = try bounds(invocation)
            return try await .encoding(registry.coverageModules(
                in: invocation.scope,
                offset: page.offset,
                limit: page.limit,
            ))
        }
        try await add(
            PortholeCoverageCapabilities.declarations.rawValue,
            summary: "Search complete source coverage, including inactive declarations, unsupported signatures, source-only modules, and excluded files. Planner support is separate from installed invocation support. Results retain scope and source hashes.",
            parameters: [.init(
                name: "query",
                summary: "{module:{rawValue:String}|null,search:String,status:all|callable|inspectableSource|unsupported|inactive|sourceOnly|excluded,offset:Int,limit:Int}. Search matches names, signatures, conditions, paths, and reasons; at most 4096 UTF-8 bytes. offset is nonnegative; limit is 1...200.",
                schema: .any,
                required: true,
            )],
            in: registry,
            scope: scope,
        ) { invocation, registry in
            guard let value = invocation.arguments["query"] else {
                throw PortholeError.invalidArguments("query is required")
            }
            return try await .encoding(registry.coverage(
                in: invocation.scope,
                query: value.decode(PortholeCoverageQuery.self),
            ))
        }
    }

    private static func installObservations(
        in registry: PortholeRegistry,
        scope: PortholeScopeToken,
    ) async throws {
        func capability(
            _ capabilityID: PortholeSymbolID,
            summary: String,
            parameters: [PortholeParameter],
            effect: PortholeEffect,
        ) -> PortholeCapability {
            .init(
                id: capabilityID,
                module: .init(rawValue: "PortholeRuntime"),
                name: capabilityID.rawValue,
                summary: summary,
                parameters: parameters,
                result: .any,
                effect: effect,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            )
        }
        let observation = PortholeParameter(
            name: "observation",
            summary: "Observation reference returned by start: {id:{rawValue:UUID},scope:{id,generation}}.",
            schema: .any,
            required: true,
        )
        try await registry.register(capability(
            PortholeObservationCapabilities.start,
            summary: "Start a callable classified read. request contains id:{rawValue:UUID}, invocation:{id,scope,capabilityID,receiver,arguments}, intervalMilliseconds:1000...60000. Retrying an identical live request returns the same observation. Each sample gets a fresh operation ID. At most 32 observations retain only their latest result, up to one MiB; sequence gaps are not recorded history.",
            parameters: [.init(
                name: "request",
                summary: "Typed observation request; choose its ID before starting so a delayed start can be stopped.",
                schema: .any,
                required: true,
            )],
            effect: .isolated,
        ), in: scope) { invocation, registry in
            guard let value = invocation.arguments["request"]
            else { throw PortholeError.invalidArguments("request is required") }
            let request = try value.decode(PortholeObservationRequest.self)
            return try await .encoding(registry.beginObservation(
                request,
                in: invocation.scope,
            ))
        }
        try await registry.register(capability(
            PortholeObservationCapabilities.read,
            summary: "Read the latest observation snapshot. Wait up to 10000 milliseconds for a sequence after afterSequence (null for any sample). A timeout returns the current snapshot. State is waiting, sample, or failed with the last good sample. Intermediate sequence values are not retained.",
            parameters: [
                observation,
                .init(
                    name: "afterSequence",
                    summary: "Last displayed sample sequence, or null",
                    schema: .optional(.integer),
                    required: true,
                ),
                integer("waitMilliseconds"),
            ],
            effect: .read,
        ), in: scope) { invocation, registry in
            guard let value = invocation.arguments["observation"],
                  case let .integer(wait) = invocation.arguments["waitMilliseconds"],
                  let waitMilliseconds = Int(exactly: wait)
            else {
                throw PortholeError
                    .invalidArguments("observation and integer waitMilliseconds are required")
            }
            let afterSequence: Int64?
            switch invocation.arguments["afterSequence"] {
                case .null: afterSequence = nil
                case let .integer(sequence): afterSequence = sequence
                case .none,
                     .some: throw PortholeError
                .invalidArguments("afterSequence must be a nonnegative integer or null")
            }
            return try await .encoding(registry.observationSnapshot(
                value.decode(PortholeObservationReference.self),
                in: invocation.scope,
                waiterID: invocation.id,
                afterSequence: afterSequence,
                waitMilliseconds: waitMilliseconds,
            ))
        }
        try await registry.register(capability(
            PortholeObservationCapabilities.stop,
            summary: "Stop an observation and release its retained arguments. Stop is idempotent and also prevents a delayed start with the same ID. Scope invalidation, disabling Porthole, and closing its owning remote connection stop observations.",
            parameters: [observation],
            effect: .isolated,
        ), in: scope) { invocation, registry in
            guard let value = invocation.arguments["observation"]
            else { throw PortholeError.invalidArguments("observation is required") }
            try await registry.endObservation(
                value.decode(PortholeObservationReference.self),
                in: invocation.scope,
            )
            return .null
        }
    }

    private struct Page { let offset: Int; let limit: Int }

    private static func bounds(_ invocation: PortholeInvocation) throws -> Page {
        guard case let .integer(offset) = invocation.arguments["offset"], offset >= 0,
              offset < Int.max,
              case let .integer(limit) = invocation.arguments["limit"], (1 ... 200).contains(limit)
        else {
            throw PortholeError
                .invalidArguments(
                    "offset must be from 0 through \(Int.max - 1); limit must be 1...200",
                )
        }
        return Page(offset: Int(offset), limit: Int(limit))
    }

    private static func string(_ key: String, _ invocation: PortholeInvocation) throws -> String {
        guard let value = invocation.arguments[key]?.stringValue
        else { throw PortholeError.invalidArguments("Missing \(key)") }
        return value
    }

    private static func text(_ name: String) -> PortholeParameter {
        PortholeParameter(name: name, summary: name, schema: .string, required: true)
    }

    private static func integer(_ name: String) -> PortholeParameter {
        PortholeParameter(name: name, summary: name, schema: .integer, required: true)
    }

    private static func add(
        _ name: String,
        summary: String,
        parameters: [PortholeParameter],
        in registry: PortholeRegistry,
        scope: PortholeScopeToken,
        handler: @escaping PortholeRegistry.Handler,
    ) async throws {
        try await registry.register(
            PortholeCapability(
                id: .init(rawValue: name),
                module: .init(rawValue: "PortholeRuntime"),
                name: name,
                summary: summary,
                parameters: parameters,
                result: .any,
                effect: .read,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            ),
            in: scope,
            handler: handler,
        )
    }
}
