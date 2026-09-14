import Foundation

public enum PortholeCoverageCapabilities {
    public static let modules = PortholeSymbolID(rawValue: "porthole.coverage.modules")
    public static let declarations = PortholeSymbolID(rawValue: "porthole.coverage")
}

/// Coverage reads use the same invocation transport and scope checks as other evidence.
public struct PortholeCoverageClient: Sendable {
    private let execute: @Sendable (PortholeInvocation) async throws -> PortholeValue

    public init(execute: @escaping @Sendable (PortholeInvocation) async throws -> PortholeValue) {
        self.execute = execute
    }

    public func modules(in scope: PortholeScopeToken, offset: Int, limit: Int) async throws
        -> PortholeCoverageModulePage
    {
        try validateRequest(offset: offset, limit: limit)
        let result = try await execute(.init(
            id: UUID(),
            scope: scope,
            capabilityID: PortholeCoverageCapabilities.modules,
            receiver: nil,
            arguments: .object([
                "offset": .integer(Int64(offset)),
                "limit": .integer(Int64(limit)),
            ]),
        ))
        let page = try result.decode(PortholeCoverageModulePage.self)
        guard page.scope == scope else { throw PortholeError.staleScope }
        try validatePage(total: page.total, count: page.items.count, offset: offset, limit: limit)
        guard Set(page.items.map(\.id)).count == page.items.count else {
            throw PortholeError.operationFailed("Coverage response contains duplicate modules.")
        }
        return page
    }

    public func declarations(
        in scope: PortholeScopeToken,
        query: PortholeCoverageQuery,
    ) async throws
        -> PortholeCoveragePage
    {
        try validateRequest(offset: query.offset, limit: query.limit)
        let result = try await execute(.init(
            id: UUID(),
            scope: scope,
            capabilityID: PortholeCoverageCapabilities.declarations,
            receiver: nil,
            arguments: .object(["query": .encoding(query)]),
        ))
        let page = try result.decode(PortholeCoveragePage.self)
        guard page.scope == scope else { throw PortholeError.staleScope }
        try validatePage(
            total: page.total,
            count: page.items.count,
            offset: query.offset,
            limit: query.limit,
        )
        guard Set(page.items.map(\.id)).count == page.items.count,
              page.items.allSatisfy({ query.module == nil || $0.module == query.module })
        else {
            throw PortholeError
                .operationFailed("Coverage response does not match its requested declaration page.")
        }
        return page
    }

    private func validateRequest(offset: Int, limit: Int) throws {
        guard offset >= 0, offset < Int.max, (1 ... 200).contains(limit) else {
            throw PortholeError
                .invalidArguments(
                    "Coverage offset must be 0 through \(Int.max - 1); limit must be 1...200.",
                )
        }
    }

    private func validatePage(total: Int, count: Int, offset: Int, limit: Int) throws {
        guard total >= 0, count <= limit,
              offset >= total ? count == 0 : count <= total - offset
        else {
            throw PortholeError
                .operationFailed("Coverage response contains invalid paging metadata.")
        }
    }
}
