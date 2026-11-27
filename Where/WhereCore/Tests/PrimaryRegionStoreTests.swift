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
        #expect(primary.allSatisfy { $0.changedByDeviceID == nil })
        #expect(try await store.persistedPrimaryRegions().isEmpty)
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
            ], changedBy: WhereCoreTestSupport.authorID)
        }

        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california, texas])
        #expect(primary.map(\.appearance) == [caLook, txLook])
        // The primary set is the tracked set.
        #expect(try await store.trackedRegions() == [.california, texas])
    }

    @Test func retiredCountryIDLeavesOtherPicksAndAppearancesIntact() async throws {
        let store = try SwiftDataStore.inMemory()
        let formerChoice = try JSONDecoder().decode(Region.self, from: Data(#""canada""#.utf8))
        let look = appearance(.red, "🍁", .starFill)
        try await store.perform {
            try await store.setPrimaryRegions([
                pick(.ontario, look, 0),
                pick(formerChoice, nil, 1),
                pick(.newYork, nil, 2),
            ], changedBy: WhereCoreTestSupport.authorID)
        }
        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.ontario, .newYork])
        #expect(primary.map(\.appearance) == [look, nil])
        #expect(try await store.trackedRegions() == [.ontario, .newYork])
    }

    @Test func aSecondEditorOnlyAuthorsChangedRegionChoices() async throws {
        let store = try SwiftDataStore.inMemory()
        let first = RecordingDeviceID(rawValue: UUID())
        let second = RecordingDeviceID(rawValue: UUID())
        let california = pick(.california, nil, 0)
        try await store.perform {
            try await store.setPrimaryRegions(
                [california, pick(.ontario, nil, 1)],
                changedBy: first,
            )
        }
        let look = appearance(.red, "🍁", .starFill)
        try await store.perform {
            try await store.setPrimaryRegions(
                [california, pick(.newYork, nil, 1), pick(.ontario, look, 2)],
                changedBy: second,
            )
        }
        let result = try await store.persistedPrimaryRegions()
        #expect(result.map(\.region) == [.california, .newYork, .ontario])
        #expect(result.map(\.changedByDeviceID) == [first, second, second])
    }

    @Test func replaceOverwritesAnExistingRowLook() async throws {
        let store = try SwiftDataStore.inMemory()
        let first = appearance(.orange, "🌴", .sunMaxFill)
        let second = appearance(.indigo, "🌉", .building2Fill)
        try await store.perform {
            try await store.setPrimaryRegions(
                [pick(.california, first, 0)],
                changedBy: WhereCoreTestSupport.authorID,
            )
        }
        try await store.perform {
            try await store.setPrimaryRegions(
                [pick(.california, second, 3)],
                changedBy: WhereCoreTestSupport.authorID,
            )
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
            ], changedBy: WhereCoreTestSupport.authorID)
        }
        // Re-committing without California removes it by omission.
        try await store.perform {
            try await store.setPrimaryRegions([
                pick(texas, appearance(.red, "🤠", .starFill), 0),
            ], changedBy: WhereCoreTestSupport.authorID)
        }
        #expect(try await store.primaryRegions().map(\.region) == [texas])
        #expect(try await store.trackedRegions() == [texas])
    }

    @Test func trackedWithoutAppearanceResolvesToNilLook() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setPrimaryRegions(
                [pick(.california, nil, 0)],
                changedBy: WhereCoreTestSupport.authorID,
            )
        }
        let primary = try await store.primaryRegions()
        #expect(primary.map(\.region) == [.california])
        #expect(primary.first?.appearance == nil)
    }
}
