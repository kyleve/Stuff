import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// The store's primary-region view: the same tracked-region rows, surfaced with
/// their picked ``RegionAppearance`` and pick order for the picker/customization
/// UI.
struct PrimaryRegionStoreTests {
    private func appearance(_ color: RegionColorToken, _ emoji: String, _ symbol: String)
        -> RegionAppearance
    {
        RegionAppearance(color: color, emoji: emoji, symbolName: symbol)
    }

    @Test func defaultsMirrorTheTrackedFallbackWhenNoRows() async throws {
        let store = try SwiftDataStore.inMemory()
        let primary = try await store.primaryRegions()
        #expect(Set(primary.map(\.region)) == SwiftDataStore.defaultTrackedRegions)
        #expect(primary.allSatisfy { $0.appearance == nil })
        // Order is dense and canonical (0..<n) so the customization step has a
        // stable sequence.
        #expect(primary.map(\.order) == Array(0 ..< primary.count))
    }

    @Test func upsertPersistsAppearanceAndOrder() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        let caLook = appearance(.orange, "🌴", "sun.max.fill")
        let txLook = appearance(.red, "🤠", "star.fill")
        try await store.perform {
            try await store.setPrimaryRegion(caLook, id: Region.california.rawValue, order: 0)
            try await store.setPrimaryRegion(txLook, id: texas.rawValue, order: 1)
        }

        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california, texas])
        #expect(primary.map(\.appearance) == [caLook, txLook])
        // The primary set is the tracked set.
        #expect(try await store.trackedRegions() == [.california, texas])
    }

    @Test func upsertOverwritesAnExistingRowLook() async throws {
        let store = try SwiftDataStore.inMemory()
        let first = appearance(.orange, "🌴", "sun.max.fill")
        let second = appearance(.indigo, "🌉", "building.2.fill")
        try await store.perform {
            try await store.setPrimaryRegion(first, id: Region.california.rawValue, order: 0)
        }
        try await store.perform {
            try await store.setPrimaryRegion(second, id: Region.california.rawValue, order: 3)
        }
        let primary = try await store.primaryRegions()
        #expect(primary.count == 1)
        #expect(primary.first?.appearance == second)
        #expect(primary.first?.order == 3)
    }

    @Test func removingAPrimaryRegionUntracksIt() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setPrimaryRegion(
                appearance(.orange, "🌴", "sun.max.fill"),
                id: Region.california.rawValue,
                order: 0,
            )
            try await store.setPrimaryRegion(
                appearance(.red, "🤠", "star.fill"),
                id: texas.rawValue,
                order: 1,
            )
        }
        try await store.perform {
            try await store.setTrackedRegion(false, id: Region.california.rawValue)
        }
        #expect(try await store.primaryRegions().map(\.region) == [texas])
    }

    @Test func trackedWithoutAppearanceResolvesToNilLook() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setTrackedRegion(true, id: Region.california.rawValue)
        }
        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california])
        #expect(primary.first?.appearance == nil)
    }
}
