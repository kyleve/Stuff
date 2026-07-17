import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The primary-region picker model: US-only options, the pick cap, ordered
/// selection, and appearance drafts.
@MainActor
struct PrimaryRegionSelectionModelTests {
    private func region(_ id: String) throws -> Region {
        try #require(Region(rawValue: id))
    }

    @Test func offersUSRegionsOnly() {
        let model = PrimaryRegionSelectionModel()
        #expect(!model.available.isEmpty)
        #expect(model.available.allSatisfy { $0.rawValue.hasPrefix("us-") })
    }

    @Test func toggleAddsAndRemovesPreservingOrder() throws {
        let model = PrimaryRegionSelectionModel()
        let tx = try region("us-TX")
        model.toggle(.california)
        model.toggle(.newYork)
        model.toggle(tx)
        #expect(model.selectedRegions == [.california, .newYork, tx])

        model.toggle(.newYork)
        #expect(model.selectedRegions == [.california, tx])
    }

    @Test func cannotSelectMoreThanTheCap() {
        let model = PrimaryRegionSelectionModel()
        // Pick the first maxSelection available regions, then attempt one more.
        let picks = Array(model.available.prefix(PrimaryRegionSelectionModel.maxSelection))
        for region in picks {
            model.toggle(region)
        }
        #expect(model.isAtCapacity)

        let extra = model.available[PrimaryRegionSelectionModel.maxSelection]
        #expect(!model.canToggle(extra))
        model.toggle(extra)
        // The add past the cap is a no-op.
        #expect(model.selectionCount == PrimaryRegionSelectionModel.maxSelection)
        #expect(!model.isSelected(extra))

        // An already-selected region can still be toggled off at capacity.
        #expect(model.canToggle(picks[0]))
    }

    @Test func appearanceDraftsDefaultThenUpdate() {
        let model = PrimaryRegionSelectionModel()
        let start = model.appearance(for: .california)
        #expect(start == RegionAppearanceCatalog.defaultAppearance(for: .california))

        model.setColor(.mint, for: .california)
        model.setEmoji("🌊", for: .california)
        model.setSymbol("water.waves", for: .california)
        let edited = model.appearance(for: .california)
        #expect(edited.color == .mint)
        #expect(edited.emoji == "🌊")
        #expect(edited.symbolName == "water.waves")
    }

    @Test func seedsFromExistingPrimaryRegions() throws {
        let tx = try region("us-TX")
        let look = RegionAppearance(color: .orange, emoji: "🤠", symbolName: "star.fill")
        let model = PrimaryRegionSelectionModel(existing: [
            PrimaryRegion(region: .california, appearance: nil, order: 0),
            PrimaryRegion(region: tx, appearance: look, order: 1),
        ])
        #expect(model.selectedRegions == [.california, tx])
        #expect(model.appearance(for: tx) == look)
    }

    @Test func ungroupedByDefault() {
        let model = PrimaryRegionSelectionModel()
        #expect(!model.isGrouped)
    }

    @Test func groupsIntoYourRegionsUsedThisYearAndMore() throws {
        let texas = try region("us-TX")
        let florida = try region("us-FL")
        let model = PrimaryRegionSelectionModel(
            existing: [PrimaryRegion(region: .california, appearance: nil, order: 0)],
            available: [.california, .newYork, texas, florida],
        )
        model.applyGrouping(usedThisYear: [.newYork])

        #expect(model.isGrouped)
        #expect(model.grouping.primary == [.california])
        #expect(model.grouping.usedThisYear == [.newYork])
        #expect(model.grouping.other == [texas, florida])
    }

    @Test func groupingIsStableWhileToggling() throws {
        let texas = try region("us-TX")
        let model = PrimaryRegionSelectionModel(
            existing: [PrimaryRegion(region: .california, appearance: nil, order: 0)],
            available: [.california, .newYork, texas],
        )
        model.applyGrouping(usedThisYear: [.newYork])

        // Add NY (from "used this year") and remove CA (from "your regions").
        model.toggle(.newYork)
        model.toggle(.california)
        // Section membership is keyed on the picks at open, so rows don't jump.
        #expect(model.grouping.primary == [.california])
        #expect(model.grouping.usedThisYear == [.newYork])
        #expect(model.grouping.other == [texas])
        // ...but the live selection reflects the toggles.
        #expect(model.selectedRegions == [.newYork])
    }

    @Test func commitPersistsPicksAsTrackedRegionsWithAppearance() async throws {
        let session = PreviewSupport.loadedSession()
        let model = PrimaryRegionSelectionModel()
        model.toggle(.california)
        model.setColor(.orange, for: .california)
        model.setEmoji("🌴", for: .california)

        try await model.commit(using: session)

        let primary = try await session.services.primaryRegions()
        #expect(primary.map(\.region) == [.california])
        #expect(primary.first?.appearance?.emoji == "🌴")
        #expect(try await session.services.trackedRegions() == [.california])
    }

    @Test func editingTheDefaultSetConvergesToUSOnly() async throws {
        // A fresh install has no stored rows, so `primaryRegions()` returns the
        // legacy default set (CA / NY / Canada / EU). Opening the editor drops
        // the non-US regions from the selection, and saving unchanged removes
        // them — the app is US-only now (documented behavior, not a bug).
        let session = PreviewSupport.loadedSession()
        let existing = try await session.services.primaryRegions()
        #expect(Set(existing.map(\.region)) == SwiftDataStore.defaultTrackedRegions)

        let model = PrimaryRegionSelectionModel(existing: existing)
        #expect(Set(model.selectedRegions) == [.california, .newYork])

        try await model.commit(using: session)
        #expect(try await session.services.trackedRegions() == [.california, .newYork])
    }

    @Test func commitUntracksRemovedRegions() async throws {
        let session = PreviewSupport.loadedSession()
        // Seed the store with two picks, then commit an edit that drops one.
        try await session.services.setPrimaryRegions([
            PrimaryRegion(
                region: .california,
                appearance: RegionAppearanceCatalog.defaultAppearance(for: .california),
                order: 0,
            ),
            PrimaryRegion(
                region: .newYork,
                appearance: RegionAppearanceCatalog.defaultAppearance(for: .newYork),
                order: 1,
            ),
        ])

        let existing = try await session.services.primaryRegions()
        let model = PrimaryRegionSelectionModel(existing: existing)
        model.toggle(.newYork) // remove NY
        try await model.commit(using: session)

        #expect(try await session.services.trackedRegions() == [.california])
    }
}
