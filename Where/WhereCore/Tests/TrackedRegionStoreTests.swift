import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// The store's tracked-region rows: one row per region so concurrent
/// cross-device edits merge, read as a `Set`, defaulting to the four until the
/// user chooses.
struct TrackedRegionStoreTests {
    @Test func defaultsToTheFourWhenNoRows() async throws {
        let store = try SwiftDataStore.inMemory()
        #expect(try await store.trackedRegions() == SwiftDataStore.defaultTrackedRegions)
    }

    @Test func addAndRemoveRoundTrip() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setTrackedRegion(true, id: Region.california.rawValue)
            try await store.setTrackedRegion(true, id: texas.rawValue)
        }
        // Once any row exists, the tracked set is exactly the rows (not the
        // default four unioned in).
        #expect(try await store.trackedRegions() == [.california, texas])

        try await store.perform {
            try await store.setTrackedRegion(false, id: Region.california.rawValue)
        }
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func duplicateAddCollapsesToOne() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setTrackedRegion(true, id: texas.rawValue)
            try await store.setTrackedRegion(true, id: texas.rawValue)
        }
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func rotatingTheDataGenerationResetsToTheDefault() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setTrackedRegion(true, id: "us-TX")
        }
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingDeviceID(rawValue: UUID()),
                at: Date(timeIntervalSinceReferenceDate: 1),
            )
        }
        #expect(try await store.trackedRegions() == SwiftDataStore.defaultTrackedRegions)
    }
}
