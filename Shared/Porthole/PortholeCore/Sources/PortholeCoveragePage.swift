import Foundation

/// Resolved states describe this installation. Inactive rows retain their separate planner support.
/// These associated-value case names are version-one wire codes; preserve them across renames.
public enum PortholeCoverageState: Sendable, Equatable, Codable {
    case callable
    case inspectableSource
    case unsupported(String)
    case inactive
    case sourceOnly(String)
    case excluded(String)
}

public enum PortholeCoverageStatusFilter: String, Sendable, Codable, CaseIterable {
    case all, callable, inspectableSource, unsupported, inactive, sourceOnly, excluded
}

public struct PortholeCoverageQuery: Sendable, Equatable, Codable {
    public let module: PortholeModuleID?
    public let search: String
    public let status: PortholeCoverageStatusFilter
    public let offset: Int
    public let limit: Int

    public init(
        module: PortholeModuleID?,
        search: String,
        status: PortholeCoverageStatusFilter,
        offset: Int,
        limit: Int,
    ) {
        self.module = module
        self.search = search
        self.status = status
        self.offset = offset
        self.limit = limit
    }
}

public struct PortholeCoverageEntry: Sendable, Equatable, Codable, Identifiable {
    public let module: PortholeModuleID
    public let declaration: PortholeDeclarationCoverage
    public let state: PortholeCoverageState
    public let installedCapabilityID: PortholeSymbolID?
    public var id: PortholeSymbolID {
        declaration.id
    }

    public init(
        module: PortholeModuleID,
        declaration: PortholeDeclarationCoverage,
        state: PortholeCoverageState,
        installedCapabilityID: PortholeSymbolID?,
    ) {
        self.module = module
        self.declaration = declaration
        self.state = state
        self.installedCapabilityID = installedCapabilityID
    }
}

public struct PortholeCoverageCounts: Sendable, Equatable, Codable {
    public let total: Int
    public let callable: Int
    public let inspectableSource: Int
    public let unsupported: Int
    public let inactive: Int
    public let sourceOnly: Int
    public let excluded: Int

    public init(
        total: Int,
        callable: Int,
        inspectableSource: Int,
        unsupported: Int,
        inactive: Int,
        sourceOnly: Int,
        excluded: Int,
    ) {
        self.total = total
        self.callable = callable
        self.inspectableSource = inspectableSource
        self.unsupported = unsupported
        self.inactive = inactive
        self.sourceOnly = sourceOnly
        self.excluded = excluded
    }
}

public struct PortholeCoverageModuleSummary: Sendable, Equatable, Codable, Identifiable {
    public let module: PortholeModuleID
    public let build: PortholeCoverageBuild
    public let sourceFileCount: Int
    public let counts: PortholeCoverageCounts
    public var id: PortholeModuleID {
        module
    }

    public init(
        module: PortholeModuleID,
        build: PortholeCoverageBuild,
        sourceFileCount: Int,
        counts: PortholeCoverageCounts,
    ) {
        self.module = module
        self.build = build
        self.sourceFileCount = sourceFileCount
        self.counts = counts
    }
}

public struct PortholeCoveragePage: Sendable, Equatable, Codable {
    public let scope: PortholeScopeToken
    public let total: Int
    public let items: [PortholeCoverageEntry]

    public init(scope: PortholeScopeToken, total: Int, items: [PortholeCoverageEntry]) {
        self.scope = scope
        self.total = total
        self.items = items
    }
}

public struct PortholeCoverageModulePage: Sendable, Equatable, Codable {
    public let scope: PortholeScopeToken
    public let total: Int
    public let items: [PortholeCoverageModuleSummary]

    public init(scope: PortholeScopeToken, total: Int, items: [PortholeCoverageModuleSummary]) {
        self.scope = scope
        self.total = total
        self.items = items
    }
}
