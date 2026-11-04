import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct CompatibilityScopedStoreTests {
    @Test func retirementBlocksReadsAndWritesWithoutDeletingData() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit()
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let home = try HomeRegionRecord(id: UUID(), region: .california, updatedAt: Date())
        try await scoped.perform { try await scoped.restoreHomeRegionRecord(home) }
        #expect(try await scoped.homeRegionRecords() == [home])

        permit.revoke()
        await #expect(throws: DataAccessPermit.AccessError.revoked) {
            try await scoped.homeRegionRecords()
        }
        await #expect(throws: DataAccessPermit.AccessError.revoked) {
            try await scoped.perform { try await scoped.setPrimaryRegions([]) }
        }
        #expect(try await base.homeRegionRecords() == [home])
        let resumed = CompatibilityScopedStore(base: base, permit: DataAccessPermit())
        #expect(try await resumed.homeRegionRecords() == [home])
    }

    @Test func revocationDuringSnapshotRejectsItsResult() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit()
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let gate = CompatibilityTestGate()
        let read = Task {
            try await scoped.readSnapshot {
                let result = try await scoped.primaryRegions()
                await gate.suspend()
                return result
            }
        }
        await gate.waitUntilEntered()
        permit.revoke()
        await gate.resume()
        await #expect(throws: DataAccessPermit.AccessError.revoked) { try await read.value }
    }
}
