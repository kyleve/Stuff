import Foundation

/// Mirrors the Core coverage wire document without linking runtime code into the build tool.
/// Real generated compiler fixtures decode and query this document through PortholeRegistry.
struct SourceCoverage: Codable {
    /// Match PortholeIdentifier's single-string wire shape without importing runtime code.
    struct Identity: Codable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(String.self)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    struct File: Codable { let path: String; let sha256: String }
    struct Location: Codable { let path: String; let line: Int }
    enum Origin: String, Codable { case generated, sourceOnly, excludedFile }
    enum Availability: Codable, Equatable {
        case callable, inspectable, unsupported(String)
    }

    struct Declaration: Codable {
        let id: Identity
        let name: String
        let kind: String
        let signature: String
        let source: Location?
        let sourceSHA256: String?
        let conditions: [String]
        let plannedAvailability: Availability
        let origin: Origin
    }

    struct Module: Codable {
        let module: Identity
        let build: SourceModule.BuildMetadata
        let files: [File]
        let declarations: [Declaration]
    }

    let version: Int
    let modules: [Module]

    init(planner: BindingPlanner, inventories: [SourceInventory]) throws {
        version = 1
        var modules = try [Self.module(planner: planner, inventory: nil)]
        for inventory in inventories {
            try modules.append(Self.module(
                planner: BindingPlanner(module: inventory.module, dependencyModules: []),
                inventory: inventory,
            ))
        }
        self.modules = modules
    }

    static func availability(unsupportedReason: String?) -> Availability {
        switch unsupportedReason {
            case .none: .callable
            case "This declaration is descriptive metadata.": .inspectable
            case let .some(reason): .unsupported(reason)
        }
    }

    private static func module(
        planner: BindingPlanner,
        inventory: SourceInventory?,
    ) throws -> Module {
        let source = planner.module
        let files = Dictionary(uniqueKeysWithValues: source.files.map { ($0.path, $0.sha256) })
        var declarations = try source.declarations.map { declaration in
            guard let hash = files[declaration.file] else {
                throw GeneratorError
                    .arguments("Coverage declaration has no source file: \(declaration.file).")
            }
            let binding = planner.plan(declaration)
            return Declaration(
                id: Identity(rawValue: declaration.declarationID),
                name: (declaration.owner.map { "\($0)." } ?? "") + declaration.name
                    + (declaration.kind == .propertySetter ? ".set" : ""),
                kind: declaration.kind.rawValue,
                signature: declaration.signature,
                source: Location(path: declaration.file, line: declaration.line),
                sourceSHA256: hash,
                conditions: declaration.conditions,
                plannedAvailability: inventory
                    .map { .unsupported($0.reason) } ??
                    availability(unsupportedReason: binding.unsupportedReason),
                origin: inventory == nil ? .generated : .sourceOnly,
            )
        }
        for file in inventory?.excludedFiles ?? [] {
            declarations.append(Declaration(
                id: Identity(rawValue: "\(source.name):excluded-source:\(file.path)"),
                name: file.path,
                kind: "excludedFile",
                signature: file.path,
                source: nil,
                sourceSHA256: nil,
                conditions: [],
                plannedAvailability: .unsupported(file.reason),
                origin: .excludedFile,
            ))
        }
        return Module(
            module: Identity(rawValue: source.name),
            build: source.build,
            files: source.files.map { File(path: $0.path, sha256: $0.sha256) },
            declarations: declarations,
        )
    }
}
