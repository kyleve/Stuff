import Foundation
@_spi(Testing) import PatchlightCore
import Testing

struct EncryptedContentCacheTests {
    @Test func contentAddressedObjectsRoundTripAndDeduplicate() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let payload = Data("snapshot pixels".utf8)

        let first = try await setup.scope.cache.insert(payload)
        let second = try await setup.scope.cache.insert(payload)

        #expect(first == second)
        #expect(try await setup.scope.cache.data(for: first) == payload)
    }

    @Test func leastRecentlyUsedObjectsEvictUnderTheConfiguredLimit() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let first = try await setup.scope.cache.insert(Data(repeating: 1, count: 400))
        let second = try await setup.scope.cache.insert(Data(repeating: 2, count: 400))

        try await setup.scope.cache.setMaximumByteCount(500)

        #expect(try await setup.scope.cache.data(for: first) == nil)
        #expect(try await setup.scope.cache.data(for: second) != nil)
        #expect(try await setup.scope.cache.storedByteCount() <= 500)
    }

    @Test func openWorkspaceObjectsSurviveEvictionAndClearCache() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let protected = try await setup.scope.cache.insert(Data(repeating: 3, count: 400))
        await setup.scope.cache.protect([protected])
        _ = try await setup.scope.cache.insert(Data(repeating: 4, count: 400))

        try await setup.scope.cache.setMaximumByteCount(200)
        try await setup.scope.cache.clear()

        #expect(try await setup.scope.cache.data(for: protected) != nil)
    }
}
