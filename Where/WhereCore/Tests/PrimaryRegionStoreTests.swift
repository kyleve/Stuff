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

    private func primary(_ region: Region, _ appearance: RegionAppearance?, _ order: Int)
        -> PrimaryRegion
    {
        PrimaryRegion(region: region, appearance: appearance, order: order)
    }

    @Test func replacePersistsAppearanceAndOrder() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        let caLook = appearance(.orange, "🌴", "sun.max.fill")
        let txLook = appearance(.red, "🤠", "star.fill")
        try await store.perform {
            try await store.setPrimaryRegions([
                primary(.california, caLook, 0),
                primary(texas, txLook, 1),
            ])
        }

        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california, texas])
        #expect(primary.map(\.appearance) == [caLook, txLook])
        // The primary set is the tracked set.
        #expect(try await store.trackedRegions() == [.california, texas])
    }

    @Test func replaceOverwritesAnExistingRowLook() async throws {
        let store = try SwiftDataStore.inMemory()
        let first = appearance(.orange, "🌴", "sun.max.fill")
        let second = appearance(.indigo, "🌉", "building.2.fill")
        try await store.perform {
            try await store.setPrimaryRegions([primary(.california, first, 0)])
        }
        try await store.perform {
            try await store.setPrimaryRegions([primary(.california, second, 3)])
        }
        let primary = try await store.primaryRegions()
        #expect(primary.count == 1)
        #expect(primary.first?.appearance == second)
        #expect(primary.first?.order == 3)
    }

    @Test func replaceRemovesOmittedRegions() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setPrimaryRegions([
                primary(.california, appearance(.orange, "🌴", "sun.max.fill"), 0),
                primary(texas, appearance(.red, "🤠", "star.fill"), 1),
            ])
        }
        // Re-committing without California removes it by omission.
        try await store.perform {
            try await store.setPrimaryRegions([
                primary(texas, appearance(.red, "🤠", "star.fill"), 0),
            ])
        }
        #expect(try await store.primaryRegions().map(\.region) == [texas])
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func trackedWithoutAppearanceResolvesToNilLook() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setPrimaryRegions([primary(.california, nil, 0)])
        }
        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california])
        #expect(primary.first?.appearance == nil)
    }
}
