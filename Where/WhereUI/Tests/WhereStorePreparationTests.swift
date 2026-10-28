import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereStorePreparationTests {
    @Test func overlappingAndCancelledWaitersShareOneOpen() async throws {
        let probe = StoreOpeningProbe()
        let preparation = WhereStorePreparation { try await probe.open() }
        let first = Task { try await preparation.get() }
        await probe.waitUntilOpen()
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return try await preparation.get()
        }
        while !secondStarted {
            await Task.yield()
        }
        first.cancel()
        #expect(await probe.count == 1)
        let store = try SwiftDataStore.inMemory()
        await probe.complete(.success(store))
        #expect(try await first.value === store)
        #expect(try await second.value === store)
        #expect(try await preparation.get() === store)
        #expect(await probe.count == 1)
    }

    @Test func aFailedOpenCanBeRetried() async throws {
        struct Failure: Error {}
        let probe = StoreOpeningProbe()
        let preparation = WhereStorePreparation { try await probe.open() }
        let first = Task { try await preparation.get() }
        await probe.waitUntilOpen()
        await probe.complete(.failure(Failure()))
        await #expect(throws: Failure.self) { try await first.value }
        let retry = Task { try await preparation.get() }
        await probe.waitUntilOpen()
        let store = try SwiftDataStore.inMemory()
        await probe.complete(.success(store))
        #expect(try await retry.value === store)
        #expect(await probe.count == 2)
    }
}
