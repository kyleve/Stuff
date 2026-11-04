import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct DataCompatibilityStorePreparationTests {
    @Test func concurrentAndCancelledWaitersShareOnePhysicalOpen() async throws {
        let store = try SwiftDataStore.inMemory()
        let gate = CompatibilityTestGate()
        let factory = ScriptedCompatibilityStoreFactory(store: store, gate: gate)
        let preparation = DataCompatibilityStorePreparation(
            hasExistingHistory: true,
            makeStore: { try await factory.open() },
        )
        #expect(try await preparation.stateBeforeOpening().hasLegacyHistory)
        #expect(await factory.openings == 0)
        let first = Task { try await preparation.open() }
        await gate.waitUntilEntered()
        let second = Task { try await preparation.open() }
        first.cancel()
        await gate.resume()
        let firstStore = try await first.value
        let secondStore = try await second.value
        #expect(firstStore as? SwiftDataStore === store)
        #expect(secondStore as? SwiftDataStore === store)
        #expect(try await preparation.open() as? SwiftDataStore === store)
        #expect(await factory.openings == 1)
    }

    @Test func failedOpenCanRetryWithoutTreatingFailureAsEmptyHistory() async throws {
        let factory = try ScriptedCompatibilityStoreFactory(
            store: SwiftDataStore.inMemory(),
            gate: nil,
        )
        await factory.setFails(true)
        let preparation = DataCompatibilityStorePreparation(
            hasExistingHistory: true,
            makeStore: { try await factory.open() },
        )
        await #expect(throws: ScriptedCompatibilityStoreFactory.OpenFailure.self) {
            try await preparation.open()
        }
        #expect(try await preparation.stateBeforeOpening().hasLegacyHistory)
        await factory.setFails(false)
        _ = try await preparation.open()
        #expect(await factory.openings == 2)
    }
}
