import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorSwiftDataStoreTests {
    @Test func cancellationDuringReopenCannotStrandAnErasedStore() async throws {
        let gate = InspectorStoreReopenGate()
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)
        try container.mainContext.save()
        let store = InspectorSwiftDataStore(
            container: container,
            modelTypes: [TestWidget.self, TestGadget.self],
            rowLimit: nil,
            valueFormatter: nil,
            makeContainer: { try await gate.open() },
            recoveryStorage: nil,
        )
        let protectedURLs = await store.storeURLs
        #expect(!protectedURLs.isEmpty)
        let erase = Task { try await store.eraseAndReopen() }
        await gate.waitUntilOpen()
        erase.cancel()
        #expect(await store.storeURLs == protectedURLs)
        await #expect(throws: InspectorSwiftDataStoreError.containerUnavailable) {
            try await store.loadEntities()
        }
        await gate.release()
        _ = try await erase.value
        #expect(await store.storeURLs == protectedURLs)
        #expect(try await store.loadEntities().allSatisfy { $0.count == 0 })
    }

    @Test func failedReopenKeepsTheOriginalStoreFamilyProtected() async throws {
        struct Failure: Error {}
        let store = try InspectorSwiftDataStore(
            container: makeContainer(),
            modelTypes: [TestWidget.self, TestGadget.self],
            rowLimit: nil,
            valueFormatter: nil,
            makeContainer: { throw Failure() },
            recoveryStorage: nil,
        )
        let protectedURLs = await store.storeURLs
        #expect(!protectedURLs.isEmpty)
        await #expect(throws: Failure.self) { try await store.eraseAndReopen() }
        #expect(await store.storeURLs == protectedURLs)
        await #expect(throws: InspectorSwiftDataStoreError.containerUnavailable) {
            try await store.loadEntities()
        }
    }
}
