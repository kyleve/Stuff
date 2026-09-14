import Foundation
import PortholeCore
import Testing

struct PortholeCoverageClientTests {
    @Test func declarationReadsUseFreshOperationsAndForwardTheTypedQuery() async throws {
        let scope = PortholeCoverageTestSupport.scope()
        let page = PortholeCoveragePage(
            scope: scope,
            total: 1,
            items: [PortholeCoverageTestSupport.entry()],
        )
        let executor = try PortholeCoverageRecordingExecutor(result: .encoding(page))
        let client = PortholeCoverageClient { invocation in await executor.invoke(invocation) }
        let query = PortholeCoverageQuery(
            module: .init(rawValue: "Fixture"),
            search: "read",
            status: .inactive,
            offset: 0,
            limit: 10,
        )
        #expect(try await client.declarations(in: scope, query: query) == page)
        #expect(try await client.declarations(in: scope, query: query) == page)
        let invocations = await executor.invocations
        #expect(Set(invocations.map(\.id)).count == 2)
        #expect(invocations
            .allSatisfy {
                $0.scope == scope && $0.capabilityID == PortholeCoverageCapabilities.declarations
            })
        #expect(try invocations.first?.arguments["query"]?
            .decode(PortholeCoverageQuery.self) == query)
    }

    @Test func modulePagesRejectAReplacedScope() async throws {
        let scope = PortholeCoverageTestSupport.scope()
        let executor = try PortholeCoverageRecordingExecutor(result: .encoding(
            PortholeCoverageModulePage(scope: scope, total: 0, items: []),
        ))
        let client = PortholeCoverageClient { invocation in await executor.invoke(invocation) }
        await #expect(throws: PortholeError.staleScope) {
            try await client.modules(in: PortholeCoverageTestSupport.scope(), offset: 0, limit: 10)
        }
    }

    @Test func malformedPageCannotSupplyMoreRowsThanItsDeclaredTotal() async throws {
        let scope = PortholeCoverageTestSupport.scope()
        let executor = try PortholeCoverageRecordingExecutor(result: .encoding(
            PortholeCoveragePage(
                scope: scope,
                total: 0,
                items: [PortholeCoverageTestSupport.entry()],
            ),
        ))
        let client = PortholeCoverageClient { invocation in await executor.invoke(invocation) }
        await #expect(throws: PortholeError
            .operationFailed("Coverage response contains invalid paging metadata."))
        {
            try await client.declarations(
                in: scope,
                query: .init(module: nil, search: "", status: .all, offset: 0, limit: 10),
            )
        }
    }

    @Test func invalidOffsetFailsBeforeExecutionAndFarOffsetDoesNotOverflow() async throws {
        let scope = PortholeCoverageTestSupport.scope()
        let executor = try PortholeCoverageRecordingExecutor(result: .encoding(
            PortholeCoverageModulePage(scope: scope, total: 1, items: []),
        ))
        let client = PortholeCoverageClient { invocation in await executor.invoke(invocation) }
        await #expect(throws: PortholeError.self) {
            try await client.modules(in: scope, offset: Int.max, limit: 10)
        }
        #expect(await executor.invocations.isEmpty)
        let page = try await client.modules(in: scope, offset: Int.max - 1, limit: 10)
        #expect(page.items.isEmpty)
    }
}
