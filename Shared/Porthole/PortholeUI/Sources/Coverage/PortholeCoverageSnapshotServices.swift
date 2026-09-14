#if DEBUG
    import Foundation
    import PortholeCore

    /// Synthetic catalog reads share the production protocols and never open resources.
    @MainActor
    final class PortholeCoverageSnapshotServices: PortholeExecuting, PortholeEvidenceReading {
        static let scope = PortholeScopeToken(
            id: .init(rawValue: "example"),
            generation: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        )
        static let sourceFile = PortholeSourceFile(
            path: "Example/Detector.swift",
            content: "func sampleCount() -> Int { 18 }\nstruct Detector {}\nfunc inspect<T>(_ value: T) {}\n#if DEBUG\nfunc diagnosticLabel() -> String { \"Synthetic\" }\n#endif\n",
        )
        static let callable = PortholeCapability(
            id: .init(rawValue: "Example.sampleCount"),
            module: .init(rawValue: "Example"),
            name: "sampleCount()",
            summary: "Read the synthetic detector sample count.",
            parameters: [],
            result: .integer,
            effect: .read,
            source: .init(path: sourceFile.path, line: 1),
            ownership: .unisolated,
            availability: .callable,
        )
        static let entries: [PortholeCoverageEntry] = [
            entry(
                name: "sampleCount()",
                line: 1,
                kind: .function,
                signature: "func sampleCount() -> Int",
                planned: .callable,
                state: .callable,
                conditions: [],
                capabilityID: callable.id,
            ),
            entry(
                name: "Detector",
                line: 2,
                kind: .type,
                signature: "struct Detector",
                planned: .inspectable,
                state: .inspectableSource,
                conditions: [],
                capabilityID: .init(rawValue: "Example.Detector"),
            ),
            entry(
                name: "inspect(_:)",
                line: 3,
                kind: .function,
                signature: "func inspect<T>(_ value: T)",
                planned: .unsupported("Unbound generic parameter T requires a concrete type."),
                state: .unsupported("Unbound generic parameter T requires a concrete type."),
                conditions: [],
                capabilityID: .init(rawValue: "Example.inspect"),
            ),
            entry(
                name: "diagnosticLabel()",
                line: 5,
                kind: .function,
                signature: "func diagnosticLabel() -> String",
                planned: .callable,
                state: .inactive,
                conditions: ["DEBUG"],
                capabilityID: nil,
            ),
        ]
        static let modules: [PortholeCoverageModuleSummary] = [
            .init(
                module: .init(rawValue: "Example"),
                build: .init(
                    configuration: "Release fixture",
                    toolchain: "Synthetic compiler identity",
                ),
                sourceFileCount: 1,
                counts: .init(
                    total: 4,
                    callable: 1,
                    inspectableSource: 1,
                    unsupported: 1,
                    inactive: 1,
                    sourceOnly: 0,
                    excluded: 0,
                ),
            ),
            .init(
                module: .init(rawValue: "PlatformDiagnostics"),
                build: .init(
                    configuration: "Release fixture",
                    toolchain: "Synthetic compiler identity",
                ),
                sourceFileCount: 1,
                counts: .init(
                    total: 2,
                    callable: 0,
                    inspectableSource: 0,
                    unsupported: 0,
                    inactive: 2,
                    sourceOnly: 0,
                    excluded: 0,
                ),
            ),
            .init(
                module: .init(rawValue: "ResourceOnly"),
                build: .init(
                    configuration: "Release fixture",
                    toolchain: "Synthetic compiler identity",
                ),
                sourceFileCount: 0,
                counts: .init(
                    total: 0,
                    callable: 0,
                    inspectableSource: 0,
                    unsupported: 0,
                    inactive: 0,
                    sourceOnly: 0,
                    excluded: 0,
                ),
            ),
        ]

        private static var allEntries: [PortholeCoverageEntry] {
            entries + entries.prefix(2).map { entry in
                let declaration = entry.declaration
                return .init(
                    module: .init(rawValue: "PlatformDiagnostics"),
                    declaration: .init(
                        id: .init(rawValue: "PlatformDiagnostics.\(declaration.name)"),
                        name: declaration.name,
                        kind: declaration.kind,
                        signature: declaration.signature,
                        source: declaration.source,
                        sourceSHA256: declaration.sourceSHA256,
                        conditions: ["os(macOS)"],
                        plannedAvailability: declaration.plannedAvailability,
                        origin: .generated,
                    ),
                    state: .inactive,
                    installedCapabilityID: nil,
                )
            }
        }

        private static func entry(
            name: String,
            line: Int,
            kind: PortholeDeclarationKind,
            signature: String,
            planned: PortholeAvailability,
            state: PortholeCoverageState,
            conditions: [String],
            capabilityID: PortholeSymbolID?,
        ) -> PortholeCoverageEntry {
            .init(
                module: .init(rawValue: "Example"),
                declaration: .init(
                    id: capabilityID ?? .init(rawValue: "Example.diagnosticLabel"),
                    name: name,
                    kind: kind,
                    signature: signature,
                    source: .init(path: sourceFile.path, line: line),
                    sourceSHA256: sourceFile.sha256,
                    conditions: conditions,
                    plannedAvailability: planned,
                    origin: .generated,
                ),
                state: state,
                installedCapabilityID: capabilityID,
            )
        }

        func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue {
            guard invocation.scope == Self.scope else { throw PortholeError.staleScope }
            switch invocation.capabilityID {
                case PortholeCoverageCapabilities.modules:
                    return try .encoding(PortholeCoverageModulePage(
                        scope: invocation.scope,
                        total: Self.modules.count,
                        items: Self.modules,
                    ))
                case PortholeCoverageCapabilities.declarations:
                    guard case let .object(arguments) = invocation.arguments,
                          let value = arguments["query"]
                    else { throw PortholeError.invalidArguments("Missing coverage query") }
                    let query = try value.decode(PortholeCoverageQuery.self)
                    let entries = Self.allEntries.filter { entry in
                        let fields = [
                            entry.declaration.name,
                            entry.declaration.signature,
                            entry.module.rawValue,
                            entry.statusReason,
                        ] + entry.declaration.conditions
                        return (query.module == nil || entry.module == query.module) &&
                            (query.search.isEmpty || fields
                                .contains { $0.localizedStandardContains(query.search) })
                    }
                    return try .encoding(PortholeCoveragePage(
                        scope: invocation.scope,
                        total: entries.count,
                        items: Array(entries.dropFirst(query.offset).prefix(query.limit)),
                    ))
                case Self.callable.id: return .integer(18)
                default: throw PortholeError.invalidArguments("Unknown synthetic capability")
            }
        }

        func capabilities(in _: PortholeScopeToken) async throws
            -> [PortholeCapability]
        {
            [Self.callable]
        }

        func objects(in _: PortholeScopeToken) async throws -> [PortholeObjectReference] {
            []
        }

        func contexts(in _: PortholeScopeToken) async throws -> [PortholeContext] {
            []
        }

        func source(path: String, in scope: PortholeScopeToken) async throws -> PortholeSourceFile {
            guard scope == Self.scope,
                  path == Self.sourceFile.path else { throw PortholeError.staleScope }
            return Self.sourceFile
        }
    }
#endif
