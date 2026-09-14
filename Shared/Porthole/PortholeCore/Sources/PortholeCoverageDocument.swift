import Foundation

/// Complete generated coverage, installed only after a module finishes registration.
/// Version one stores source hashes, not a duplicate source archive.
public struct PortholeCoverageDocument: Sendable, Equatable, Codable {
    public let version: Int
    public let modules: [PortholeModuleCoverage]

    public init(version: Int, modules: [PortholeModuleCoverage]) {
        self.version = version
        self.modules = modules
    }
}

public struct PortholeCoverageBuild: Sendable, Equatable, Codable {
    public let configuration: String
    public let toolchain: String

    public init(configuration: String, toolchain: String) {
        self.configuration = configuration
        self.toolchain = toolchain
    }
}

public struct PortholeCoverageFile: Sendable, Equatable, Codable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) {
        self.path = path
        self.sha256 = sha256
    }
}

public struct PortholeModuleCoverage: Sendable, Equatable, Codable {
    public let module: PortholeModuleID
    public let build: PortholeCoverageBuild
    public let files: [PortholeCoverageFile]
    public let declarations: [PortholeDeclarationCoverage]

    public init(
        module: PortholeModuleID,
        build: PortholeCoverageBuild,
        files: [PortholeCoverageFile],
        declarations: [PortholeDeclarationCoverage],
    ) {
        self.module = module
        self.build = build
        self.files = files
        self.declarations = declarations
    }
}

public enum PortholeDeclarationKind: String, Sendable, Codable {
    case type, function, initializer, property, propertySetter, enumerationCase, typeAlias,
         subscriptDeclaration, deinitializer, typeExtension, excludedFile
}

public enum PortholeCoverageOrigin: String, Sendable, Codable {
    case generated, sourceOnly, excludedFile
}

/// Planner support is independent of inclusion in this build. It never grants invocation access.
public struct PortholeDeclarationCoverage: Sendable, Equatable, Codable, Identifiable {
    public let id: PortholeSymbolID
    public let name: String
    public let kind: PortholeDeclarationKind
    public let signature: String
    public let source: PortholeSourceLocation?
    public let sourceSHA256: String?
    public let conditions: [String]
    public let plannedAvailability: PortholeAvailability
    public let origin: PortholeCoverageOrigin

    public init(
        id: PortholeSymbolID,
        name: String,
        kind: PortholeDeclarationKind,
        signature: String,
        source: PortholeSourceLocation?,
        sourceSHA256: String?,
        conditions: [String],
        plannedAvailability: PortholeAvailability,
        origin: PortholeCoverageOrigin,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.signature = signature
        self.source = source
        self.sourceSHA256 = sourceSHA256
        self.conditions = conditions
        self.plannedAvailability = plannedAvailability
        self.origin = origin
    }
}
