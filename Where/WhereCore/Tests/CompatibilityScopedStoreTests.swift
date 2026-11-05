import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct CompatibilityScopedStoreTests {
    @Test func verifiedAccountContractDoesNotPretendItsMetadataAlreadyReachedTheStore(
    ) async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit(
            policy: RecordingChoiceTestSupport.policy,
            requiredMajor: 1,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        #expect(try await base.dataContractMajor() == 0)
        #expect(try await scoped.dataContractMajor() == 1)
        #expect(try await scoped.dataCompatibilityState().persistedRequiredMajor == nil)
        #expect(try await scoped.dataCompatibilityState().recordMajors.isEmpty)
        #expect(try await base.dataContractMajor() == 0)
        permit.revoke()
        await #expect(throws: DataAccessPermit.AccessError.revoked) {
            try await scoped.dataContractMajor()
        }
    }

    @Test func understandingANewerContractDoesNotActivateAnOlderAccount() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit(
            policy: RecordingChoiceTestSupport.policy,
            requiredMajor: 0,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let source = RecordingChoiceCoordinator(
            store: scoped,
            policy: RecordingChoiceTestSupport.policy,
            author: RecordingChoiceTestSupport.author,
            geography: HistoryRegionAttribution(),
            onCommitted: {},
        )
        let controls = RecordingControlEditCoordinator(
            store: scoped,
            policy: RecordingChoiceTestSupport.policy,
            author: RecordingChoiceTestSupport.author,
            onCommitted: {},
        )
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await source.review(RecordingChoiceTestSupport.request())
        }
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await controls.review(RecordingControlEditTestSupport.edit(.ignore, removes: false))
        }
        #expect(try await scoped.dataContractMajor() == 0)
    }

    @Test func retirementBlocksReadsAndWritesWithoutDeletingData() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit(
            policy: .foundation,
            requiredMajor: 0,
            onCompatibilityFailure: { _ in },
        )
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
        let resumed = CompatibilityScopedStore(
            base: base,
            permit: DataAccessPermit(
                policy: .foundation,
                requiredMajor: 0,
                onCompatibilityFailure: { _ in },
            ),
        )
        #expect(try await resumed.homeRegionRecords() == [home])
    }

    @Test func revocationDuringSnapshotRejectsItsResult() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit(
            policy: .foundation,
            requiredMajor: 0,
            onCompatibilityFailure: { _ in },
        )
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
