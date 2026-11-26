import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// The store's tracked-region rows: one row per region so concurrent
/// cross-device edits merge, read as a `Set`, using the defaults until the
/// user chooses.
struct TrackedRegionStoreTests {
    @Test func usesTheDefaultTrackingChoicesWhenNoRowsExist() async throws {
        let store = try SwiftDataStore.inMemory()
        let defaults = try await store.trackedRegions()
        #expect(defaults == [.california, .newYork, .europeanUnion])
        #expect(defaults == Set(RegionAttributor.shared.loadedRegions))
    }

    @Test func addAndRemoveRoundTrip() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setTrackedRegion(true, region: .california)
            try await store.setTrackedRegion(true, region: texas)
        }
        // Once any row exists, the tracked set is exactly the rows (not the
        // implicit defaults unioned in).
        #expect(try await store.trackedRegions() == [.california, texas])

        try await store.perform {
            try await store.setTrackedRegion(false, region: .california)
        }
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func duplicateAddCollapsesToOne() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setTrackedRegion(true, region: texas)
            try await store.setTrackedRegion(true, region: texas)
        }
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func rotatingTheDataGenerationResetsToTheDefault() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setTrackedRegion(true, region: texas)
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
