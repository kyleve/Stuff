import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct SwiftDataStoreCompatibilityTests {
    @Test @MainActor func unknownAndMalformedRequirementsNeverAppearCompatible() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        #expect(try await store.dataCompatibility().isCompatible)
        let context = ModelContext(container)
        let row = SDDataCompatibilityRequirement(version: CompatibilityTestSupport.nextVersion)
        context.insert(row)
        try context.save()
        let status = try await store.dataCompatibility()
        #expect(status.requiredVersion == CompatibilityTestSupport.nextVersion)
        await #expect(throws: DataCompatibilityError.updateRequired(status)) {
            try await store.allSamples()
        }
        await #expect(throws: DataCompatibilityError.updateRequired(status)) {
            try await store.perform {}
        }
        await #expect(throws: DataCompatibilityError.updateRequired(status)) {
            try await store.readSnapshot { 42 }
        }
        // Installation metadata remains publishable while ordinary data is blocked.
        let deviceID = RecordingDeviceID(rawValue: UUID())
        try await store.publishDataCapability(for: deviceID, at: CompatibilityTestSupport.now)
        #expect(try await store.deviceDataCapabilities().first?.supportedVersion == .current)
        row.requiredVersion = nil
        try context.save()
        await #expect(throws: DataCompatibilityError.invalidMetadata) {
            try await store.dataCompatibility()
        }
        await #expect(throws: DataCompatibilityError.invalidMetadata) {
            try await store.allSamples()
        }
    }

    @Test @MainActor func requirementSurvivesRotationAndReopening() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        await store
            .setSupportedDataCompatibilityVersionForTesting(CompatibilityTestSupport.nextVersion)
        try await store.perform {
            try await store.requireDataCompatibility(CompatibilityTestSupport.nextVersion)
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: .init(rawValue: UUID()),
                at: CompatibilityTestSupport.now,
            )
        }
        try await store.perform {
            try await store.requireDataCompatibility(.initial)
            _ = try await store.rotateDataGeneration(
                reason: .backupReplace,
                changedBy: .init(rawValue: UUID()),
                at: CompatibilityTestSupport.now.addingTimeInterval(1),
            )
        }
        let reopened = SwiftDataStore(modelContainer: container)
        #expect(try await reopened.dataCompatibility().requiredVersion == CompatibilityTestSupport
            .nextVersion)
        #expect(try await !reopened.dataCompatibility().isCompatible)
    }

    @Test func latestCapabilityCanAdvertiseADowngrade() async throws {
        let world = try await CompatibilityTestSupport.makeWorld()
        try await world.store.publishDataCapability(
            for: world.phone,
            at: CompatibilityTestSupport.now,
        )
        await world.store.setSupportedDataCompatibilityVersionForTesting(.initial)
        try await world.store.publishDataCapability(for: world.phone, at: .distantPast)
        let capability = try #require(await world.store.deviceDataCapabilities().first)
        #expect(capability.revision == 1)
        #expect(capability.supportedVersion == .initial)
    }

    @Test func metadataTransactionCannotWriteUserData() async throws {
        let store = try SwiftDataStore.inMemory()
        await #expect(throws: DataCompatibilityError.metadataTransactionCannotWriteDomainData) {
            try await store.performCompatibilityMaintenance {
                try await store.add(sample: CompatibilityTestSupport.sample)
            }
        }
        #expect(try await store.allSamples().isEmpty)
    }

    @Test @MainActor func externallyRaisedRequirementRejectsSuspendedWriteBeforeSave() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let (arrivals, arrived) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (releases, release) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let writer = Task {
            try await store.perform {
                try await store.add(sample: CompatibilityTestSupport.sample)
                arrived.yield()
                for await _ in releases {
                    break
                }
            }
        }
        for await _ in arrivals {
            break
        }
        let external = ModelContext(container)
        external
            .insert(SDDataCompatibilityRequirement(version: CompatibilityTestSupport.nextVersion))
        try external.save()
        release.yield()
        release.finish()
        let status = try await store.dataCompatibility()
        await #expect(throws: DataCompatibilityError.updateRequired(status)) {
            try await writer.value
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<SDLocationSample>()).isEmpty)
    }
}
