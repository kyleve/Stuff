import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct SwiftDataStoreCompatibilityTests {
    enum Read: CaseIterable {
        case allSamples, samples, versionedRecords
    }

    @Test(arguments: Read.allCases)
    @MainActor func malformedHeaderArrivingAfterAdmissionRevokesThePermit(read: Read) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let base = SwiftDataStore(modelContainer: container)
        let permit = DataAccessPermit(
            policy: .foundation,
            requiredMajor: 0,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let gate = CompatibilityTestGate()
        await base.afterNextCompatibilityRead { await gate.suspend() }
        let operation = Task {
            switch read {
                case .allSamples: _ = try await scoped.allSamples()
                case .samples: _ = try await scoped.samples(in: DateInterval(
                        start: Date(),
                        duration: 1,
                    ))
                case .versionedRecords:
                    _ = try await scoped
                        .versionedHistoryRecords(policy: RecordingBackupTestSupport.policy)
            }
        }
        await gate.waitUntilEntered()
        let remote = ModelContext(container)
        let row = SDVersionedHistoryRecord()
        row.envelope = Data("malformed".utf8)
        remote.insert(row)
        try remote.save()
        await gate.resume()
        await #expect(throws: DecodingError.self) { try await operation.value }
        #expect(permit.isRevoked)
        await #expect(throws: DecodingError.self) { try await base.allSamples() }
    }

    @Test(arguments: Read.allCases, [false, true])
    @MainActor func headerArrivingAfterAdmissionCannotExpandTheReadPermit(
        read: Read,
        understandsRecordingContract: Bool,
    ) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let base = SwiftDataStore(modelContainer: container)
        let permit = DataAccessPermit(
            policy: understandsRecordingContract ? DataCompatibilityTestSupport
                .policy : .foundation,
            requiredMajor: 0,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let gate = CompatibilityTestGate()
        await base.afterNextCompatibilityRead { await gate.suspend() }
        let operation = Task {
            switch read {
                case .allSamples: _ = try await scoped.allSamples()
                case .samples:
                    _ = try await scoped.samples(in: DateInterval(
                        start: sample.timestamp,
                        duration: 1,
                    ))
                case .versionedRecords:
                    // Decoder support is not authorization to use a newly observed contract.
                    _ = try await scoped
                        .versionedHistoryRecords(policy: RecordingBackupTestSupport.policy)
            }
        }
        await gate.waitUntilEntered()
        let remote = ModelContext(container)
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(VersionedLocationSample.encode(
            sample,
            generationID: .initial,
        ))
        remote.insert(row)
        try remote.save()
        await gate.resume()
        let expected: DataCompatibilityError = understandsRecordingContract
            ? .verificationRequired : .updateRequired(requiredMajor: 1)
        await #expect(throws: expected) { try await operation.value }
        #expect(permit.isRevoked)
        #expect(try await base.allSamples() == [sample])
    }

    @Test func cachedMetadataTracksLegacyWritesAndFloorChangesWithinOneTransaction() async throws {
        let store = try SwiftDataStore.inMemory()
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        try await store.perform {
            #expect(try await !store.dataCompatibilityState().hasLegacyHistory)
            try await store.add(sample: sample)
            let legacy = try await store.dataCompatibilityState()
            #expect(legacy.hasLegacyHistory)
            #expect(legacy.persistedRequiredMajor == nil)
            try await store.raiseRequiredDataMajor(1)
            let activated = try await store.dataCompatibilityState()
            #expect(activated.persistedRequiredMajor == 1)
            #expect(activated.requiredMajor == 1)
            try await store.add(sample: sample)
            #expect(try await store.allSamples() == [sample])
        }
    }

    @Test func ordinaryOlderScopeCannotActivateOrAuthorANewerMajor() async throws {
        let store = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit(
            policy: DataCompatibilityTestSupport.policy,
            requiredMajor: 0,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: store, permit: permit)
        let record = VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 0, patch: 0),
            scope: .entireHistory,
            kind: "fixture",
            payload: Data(),
        )
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await scoped.perform { try await scoped.raiseRequiredDataMajor(1) }
        }
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await scoped.perform { try await scoped.addVersionedHistoryRecord(record) }
        }
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == nil)
        #expect(try await store.versionedHistoryRecords(policy: DataCompatibilityTestSupport.policy)
            .isEmpty)
        try permit.validate()
    }

    @Test func supportedMajorImportedDuringAWriteStillRequiresANewScope() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let scoped = CompatibilityScopedStore(
            base: store,
            permit: DataAccessPermit(
                policy: DataCompatibilityTestSupport.policy,
                requiredMajor: 0,
                onCompatibilityFailure: { _ in },
            ),
        )
        let gate = CompatibilityTestGate()
        let home = try HomeRegionRecord(id: UUID(), region: .california, updatedAt: Date())
        let operation = Task {
            try await scoped.perform {
                try await scoped.restoreHomeRegionRecord(home)
                await gate.suspend()
            }
        }
        await gate.waitUntilEntered()
        let remote = ModelContext(container)
        let requirement = SDDataCompatibilityRequirement()
        requirement.requiredMajor = 1
        remote.insert(requirement)
        try remote.save()
        await gate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) {
            try await operation.value
        }
        #expect(try await store.homeRegionRecords().isEmpty)
    }

    @Test func lowerRequirementsAndResetCannotLowerTheFloor() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.raiseRequiredDataMajor(2) }
        try await store.perform {
            try await store.raiseRequiredDataMajor(0)
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: .init(rawValue: UUID()),
                at: Date(),
            )
        }
        #expect(try await store.dataCompatibilityState().requiredMajor == 2)
    }

    @Test func incompatibleRecordArrivingBeforeMetadataBlocksReads() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let row = SDVersionedHistoryRecord()
        row
            .envelope = Data(
                #"{"semantics":{"major":2,"minor":0,"patch":0},"payload":{"unreadable":true}}"#
                    .utf8,
            )
        let remote = ModelContext(container)
        remote.insert(row)
        try remote.save()
        let permit = DataAccessPermit(
            policy: DataCompatibilityTestSupport.policy,
            requiredMajor: 1,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: store, permit: permit)
        await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
            try await scoped.allSamples()
        }
        #expect(throws: DataAccessPermit.AccessError.revoked) { try permit.validate() }
        try await store.perform { try await store.raiseRequiredDataMajor(0) }
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == 2)
    }

    @Test func requirementImportedDuringAWriteRejectsThePhysicalSave() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let scoped = CompatibilityScopedStore(
            base: store,
            permit: DataAccessPermit(
                policy: .foundation,
                requiredMajor: 0,
                onCompatibilityFailure: { _ in },
            ),
        )
        let gate = CompatibilityTestGate()
        let home = try HomeRegionRecord(id: UUID(), region: .california, updatedAt: Date())
        let operation = Task {
            try await scoped.perform {
                try await scoped.restoreHomeRegionRecord(home)
                await gate.suspend()
            }
        }
        await gate.waitUntilEntered()
        let remote = ModelContext(container)
        let requirement = SDDataCompatibilityRequirement()
        requirement.requiredMajor = 1
        remote.insert(requirement)
        try remote.save()
        await gate.resume()
        await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 1)) {
            try await operation.value
        }
        #expect(try await store.homeRegionRecords().isEmpty)
    }
}
