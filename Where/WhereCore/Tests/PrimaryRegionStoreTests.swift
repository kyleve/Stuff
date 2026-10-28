import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// The store's primary-region view: the same tracked-region rows, surfaced with
/// their picked ``RegionAppearance`` and pick order for the picker/customization
/// UI.
struct PrimaryRegionStoreTests {
    private func appearance(_ color: RegionColorToken, _ emoji: String, _ symbol: RegionSymbol)
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

    private func pick(_ region: Region, _ appearance: RegionAppearance?, _ order: Int)
        -> PrimaryRegion
    {
        PrimaryRegion(region: region, appearance: appearance, order: order)
    }

    @Test func replacePersistsAppearanceAndOrder() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        let caLook = appearance(.orange, "🌴", .sunMaxFill)
        let txLook = appearance(.red, "🤠", .starFill)
        try await store.perform {
            try await store.setPrimaryRegions([
                pick(.california, caLook, 0),
                pick(texas, txLook, 1),
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
        let first = appearance(.orange, "🌴", .sunMaxFill)
        let second = appearance(.indigo, "🌉", .building2Fill)
        try await store.perform {
            try await store.setPrimaryRegions([pick(.california, first, 0)])
        }
        try await store.perform {
            try await store.setPrimaryRegions([pick(.california, second, 3)])
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
                pick(.california, appearance(.orange, "🌴", .sunMaxFill), 0),
                pick(texas, appearance(.red, "🤠", .starFill), 1),
            ])
        }
        // Re-committing without California removes it by omission.
        try await store.perform {
            try await store.setPrimaryRegions([
                pick(texas, appearance(.red, "🤠", .starFill), 0),
            ])
        }
        #expect(try await store.primaryRegions().map(\.region) == [texas])
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func trackedWithoutAppearanceResolvesToNilLook() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setPrimaryRegions([pick(.california, nil, 0)])
        }
        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california])
        #expect(primary.first?.appearance == nil)
    }
}
