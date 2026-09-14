import Foundation
@testable import PortholeRuntime
import Testing

struct PortholeReadReceiptCacheTests {
    @Test func evictsOldestReceiptsAndReleasesInvalidatedScopes() throws {
        let scope = PortholeScopeToken(id: .init(rawValue: "test"), generation: UUID())
        var cache = PortholeReadReceiptCache(maximumCount: 2, maximumBytes: 4096)
        let first = record(scope: scope, value: "first")
        let second = record(scope: scope, value: "second")
        let third = record(scope: scope, value: "third")
        try cache.insert(first); try cache.insert(second); try cache.insert(third)
        #expect(cache.count == 2)
        #expect(cache.record(for: first.id) == nil)
        #expect(cache.record(for: second.id) == second)
        cache.remove(scope: scope)
        #expect(cache.count == 0)
        #expect(cache.encodedBytes == 0)
    }

    @Test func encodedByteBudgetRejectsOversizedResultsWithoutDiscardingOtherReceipts() throws {
        let scope = PortholeScopeToken(id: .init(rawValue: "test"), generation: UUID())
        let first = record(scope: scope, value: "first")
        let second = record(scope: scope, value: "second")
        let maximum = try JSONEncoder().encode(first).count + JSONEncoder().encode(second).count - 1
        var cache = PortholeReadReceiptCache(maximumCount: 100, maximumBytes: maximum)
        try cache.insert(first); try cache.insert(second)
        #expect(cache.count == 1)
        #expect(cache.record(for: first.id) == nil)
        try cache.insert(record(scope: scope, value: String(repeating: "x", count: maximum)))
        #expect(cache.count == 1)
        #expect(cache.record(for: second.id) == second)
        #expect(cache.encodedBytes <= maximum)
        cache.removeAll()
        #expect(cache.encodedBytes == 0)
    }

    private func record(scope: PortholeScopeToken, value: String) -> PortholeOperationRecord {
        PortholeOperationRecord(
            invocation: PortholeRuntimeTestSupport.invocation(scope: scope),
            status: .succeeded(.string(value)),
        )
    }
}
