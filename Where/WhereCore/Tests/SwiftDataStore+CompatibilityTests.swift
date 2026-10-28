import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct SwiftDataStoreCompatibilityTests {
    @Test func unsupportedRequirementBlocksWritesButAllowsTeardownReads() async throws {
        let store = try SwiftDataStore.inMemory()
        let home = try HomeRegionRecord(id: UUID(), region: .california, updatedAt: Date())
        let required = DataCompatibilityVersion(rawValue: 2)
        try await store.perform {
            try await store.addDataCompatibilityRequirement(.init(id: UUID(), version: required))
        }
        #expect(try await store.homeRegionRecords().isEmpty)
        await #expect(throws: DataCompatibilityError.updateRequired(required)) {
            try await store.perform { try await store.restoreHomeRegionRecord(home) }
        }
        await #expect(throws: DataCompatibilityError.updateRequired(required)) {
            try await store.perform { try await store.replaceHomeRegionRecord(with: home) }
        }
        await store.setSupportedDataCompatibilityVersionForTesting(required)
        #expect(try await store.homeRegionRecords().isEmpty)
    }

    @Test func unsupportedPendingRequirementRollsBackTheFirstDomainWrite() async throws {
        let store = try SwiftDataStore.inMemory()
        await #expect(throws: DataCompatibilityError.updateRequired(.init(rawValue: 2))) {
            try await store.perform {
                try await store.add(sample: Self.sample)
                try await store.addDataCompatibilityRequirement(.init(
                    id: UUID(),
                    version: .init(rawValue: 2),
                ))
            }
        }
        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.dataCompatibilityRequirements().isEmpty)
    }

    @Test func remoteRequirementRejectsSuspendedWriteBeforeSave() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let remote = SwiftDataStore(modelContainer: container)
        let (started, ready) = AsyncStream.makeStream(of: Void.self)
        let (release, resume) = AsyncStream.makeStream(of: Void.self)
        let writing = Task {
            try await store.perform {
                try await store.add(sample: Self.sample)
                ready.yield(); ready.finish()
                for await _ in release {}
            }
        }
        for await _ in started {}
        try await remote.perform {
            try await remote.addDataCompatibilityRequirement(.init(
                id: UUID(),
                version: .init(rawValue: 2),
            ))
        }
        resume.finish()
        await #expect(throws: DataCompatibilityError.updateRequired(.init(rawValue: 2))) {
            try await writing.value
        }
        await store.setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func revokedScopeRejectsItsSuspendedWriteAndCannotResume() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit()
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let (started, ready) = AsyncStream.makeStream(of: Void.self)
        let (release, resume) = AsyncStream.makeStream(of: Void.self)
        let writing = Task {
            try await scoped.perform {
                try await scoped.add(sample: Self.sample)
                ready.yield(); ready.finish()
                for await _ in release {}
            }
        }
        for await _ in started {}
        permit.revoke()
        resume.finish()
        await #expect(throws: DataCompatibilityError.accessRevoked) { try await writing.value }
        #expect(try await base.allSamples().isEmpty)
        #expect(try await scoped.allSamples().isEmpty)
        let replacement = CompatibilityScopedStore(base: base, permit: DataAccessPermit())
        try await replacement.perform { try await replacement.add(sample: Self.sample) }
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await scoped.perform { try await scoped.add(sample: Self.sample) }
        }
        #expect(try await base.allSamples().count == 1)
    }

    @Test func malformedRequirementsBlockWritesWithoutHidingMetadata() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let context = ModelContext(container)
        context.insert(SDDataCompatibilityRequirement())
        try context.save()
        let store = SwiftDataStore(modelContainer: container)
        await #expect(throws: DataCompatibilityError.self) {
            try await store.perform { try await store.add(sample: Self.sample) }
        }
        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.recordingAuthorityCommits().isEmpty)
    }

    @Test func resetByUpdatedBuildCannotLowerRequirement() async throws {
        let store = try SwiftDataStore.inMemory()
        await store.setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        try await store.perform {
            try await store.addDataCompatibilityRequirement(.init(
                id: UUID(),
                version: .init(rawValue: 2),
            ))
            _ = try await store.rotateDataGeneration(
                reason: .historyReset,
                changedBy: .init(rawValue: UUID()),
                at: Date(),
            )
        }
        await store.setSupportedDataCompatibilityVersionForTesting(.initial)
        #expect(try await store.requiredDataCompatibilityVersion() == .init(rawValue: 2))
        await #expect(throws: DataCompatibilityError.updateRequired(.init(rawValue: 2))) {
            try await store.perform { try await store.add(sample: Self.sample) }
        }
    }

    private static var sample: LocationSample {
        .init(
            timestamp: Date(),
            coordinate: .init(latitude: 40, longitude: -100),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }
}
