import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct StandaloneDataCompatibilityTests {
    @Test func extensionsCannotAdvanceOrUseAnUnsupportedContract() throws {
        #expect(throws: Never.self) { try StandaloneDataCompatibility.validate(
            required: .initial,
            supported: .initial,
        ) }
        #expect(throws: DataCompatibilityError.recordingDeviceUpdateRequired) {
            try StandaloneDataCompatibility.validate(
                required: .initial,
                supported: .init(rawValue: 2),
            )
        }
        #expect(throws: DataCompatibilityError.updateRequired(.init(rawValue: 2))) {
            try StandaloneDataCompatibility.validate(
                required: .init(rawValue: 2),
                supported: .initial,
            )
        }
    }

    @Test func incompatibleShareTransactionCannotMutateTheStore() async throws {
        let store = try SwiftDataStore.inMemory()
        let original = try await store.trackedRegions()
        try await store.perform { try await store.addDataCompatibilityRequirement(.init(
            id: UUID(),
            version: .init(rawValue: 2),
        )) }
        await #expect(throws: DataCompatibilityError.self) {
            try await store.perform {
                try await StandaloneDataCompatibility.requireAccess(to: store)
                try await store.setTrackedRegion(
                    !original.contains(.california),
                    region: .california,
                )
            }
        }
        await store.setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        #expect(try await store.trackedRegions() == original)
    }
}
