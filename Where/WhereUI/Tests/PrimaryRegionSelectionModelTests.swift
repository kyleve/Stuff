import AccessibilitySnapshotParser
import RegionKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereCore
@testable import WhereUI

/// The primary-region picker model: North American options, the pick cap, ordered
/// selection, and appearance drafts.
@MainActor
struct PrimaryRegionSelectionModelTests {
    private func region(_ id: String) throws -> Region {
        try #require(Region(rawValue: id))
    }

    @Test func offersNorthAmericanLoggingChoicesInCatalogOrder() throws {
        let model = PrimaryRegionSelectionModel()
        let available = model.available
        #expect(available == RegionCatalog.shared.all.filter { $0 != .europeanUnion })
        #expect(available.count == 65)
        #expect(PrimaryRegionSelectionModel.usRegions.count == 52)
        #expect(PrimaryRegionSelectionModel.usRegions == available
            .filter { $0.rawValue.hasPrefix("us-") })
        #expect(try available.contains(region("ca-ON")))
        #expect(try available.contains(region("ca-NU")))
        #expect(!available.contains(.other))
        for id in ["canada", "united-states"] {
            let country = try JSONDecoder().decode(Region.self, from: JSONEncoder().encode(id))
            #expect(!available.contains(country))
            #expect(!model.canToggle(country))
            model.toggle(country)
        }
        #expect(model.selectedRegions.isEmpty)
    }

    @Test func browseGroupsKeepOfferedRegionsTogetherInOrder() {
        let model = PrimaryRegionSelectionModel(
            available: [.newYork, .ontario, .other, .california, .europeanUnion],
        )
        model.toggle(.ontario)
        #expect(model.countryGroups.map { $0.country?.id.rawValue } == [
            "united-states",
            "canada",
            nil,
        ])
        #expect(model.countryGroups.map(\.regions) == [
            [.newYork, .california],
            [.ontario],
            [.other, .europeanUnion],
        ])
    }

    @Test func postalCodePrecedesOtherNameMatchesAcrossCountries() throws {
        let washington = try region("us-WA")
        let model = PrimaryRegionSelectionModel(available: [washington, .ontario, .newYork])
        model.toggle(.newYork)
        model.searchText = "  oN\n"
        #expect(model.filteredRegions == [.ontario, washington])
        model.searchText = "ny"
        #expect(model.filteredRegions == [.newYork])
        model.searchText = "alaska"
        #expect(model.filteredRegions.isEmpty)
        model.searchText = "  \n"
        #expect(model.isSearching == false)
        #expect(model.filteredRegions == model.available)
        #expect(model.selectedRegions == [.newYork])
    }

    @Test func searchMatchesAccentsInLocalizedNames() throws {
        let quebec = try region("ca-QC")
        let model = PrimaryRegionSelectionModel()
        model.searchText = "québ"
        #expect(model.filteredRegions == [quebec])
    }

    @Test func hostedPickerSelectsAndReopensTwoProvinces() async throws {
        let quebec = try region("ca-QC")
        let session = PreviewSupport.loadedSession()
        let model = PrimaryRegionSelectionModel()
        model.applyGrouping(usedThisYear: [.ontario, quebec])
        let host = UIHostingController(rootView: NavigationStack {
            RegionPickerView(model: model)
        }.whereBroadwayRoot())
        try await show(host) { controller in
            for region in [Region.ontario, quebec] {
                @MainActor func row() -> NSObject? {
                    HostedAccessibility.objects(in: controller.view).first {
                        $0.accessibilityLabel == region.localizedName && $0.accessibilityTraits
                            .contains(.button)
                    }
                }
                try await waitForAsync { row() != nil }
                let button = try #require(row())
                if let control = button as? UIControl {
                    control.sendActions(for: .touchUpInside)
                } else {
                    try #require(button.accessibilityActivate())
                }
                try await waitForAsync { model.isSelected(region) }
            }
        }
        try await model.commit(using: session)
        let reopened = try await session.services.primaryRegions()
        #expect(PrimaryRegionSelectionModel(existing: reopened).selectedRegions == [
            .ontario,
            quebec,
        ])
    }

    @Test func hostedPickerKeepsSelectionsAndCountryExpansionThroughSearch() async throws {
        let model = PrimaryRegionSelectionModel(available: [.newYork, .ontario])
        let canada = try #require(RegionCatalog.shared.node(id: .init(rawValue: "canada")))
        let host = UIHostingController(rootView: NavigationStack {
            RegionPickerView(model: model)
        }.whereBroadwayRoot())
        try await show(host) { controller in
            @MainActor func button(_ label: String) -> NSObject? {
                HostedAccessibility.objects(in: controller.view).first {
                    $0.accessibilityTraits.contains(.button)
                        && $0.accessibilityLabel?.hasPrefix(label) == true
                }
            }
            @MainActor func tap(_ label: String) async throws {
                try await waitForAsync { button(label) != nil }
                let element = try #require(button(label))
                if let control = element as? UIControl {
                    control.sendActions(for: .touchUpInside)
                } else {
                    try #require(element.accessibilityActivate(), "Activate \(label)")
                }
            }

            try await tap(canada.localizedName)
            try await tap(Region.ontario.localizedName)
            try await waitForAsync { model.selectedRegions == [.ontario] }

            let field = try #require(HostedAccessibility.objects(in: controller.view)
                .compactMap { $0 as? UITextField }.first)
            field.text = "NY"
            field.sendActions(for: .editingChanged)
            try await waitForAsync {
                button(Region.newYork.localizedName)?.accessibilityValue == "US · NY"
            }
            try await tap(Region.newYork.localizedName)
            try await waitForAsync { model.selectedRegions == [.ontario, .newYork] }
            try await tap(WhereFormat.regionPickerRemoveSelection(.ontario))
            try await waitForAsync { model.selectedRegions == [.newYork] }

            try await tap(String(localized: .regionPickerClearSearch))
            try await waitForAsync { button(Region.ontario.localizedName) != nil }
            #expect(model.searchText.isEmpty)
        }
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
        model.setSymbol(.waterWaves, for: .california)
        let edited = model.appearance(for: .california)
        #expect(edited.color == .mint)
        #expect(edited.emoji == "🌊")
        #expect(edited.symbolName == .waterWaves)
    }

    @Test func seedsFromExistingPrimaryRegions() throws {
        let tx = try region("us-TX")
        let look = RegionAppearance(color: .orange, emoji: "🤠", symbolName: .starFill)
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

    @Test func editingOneAppearancePreservesOtherRegionsAndOrder() async throws {
        let session = PreviewSupport.loadedSession()
        let california = RegionAppearance(color: .orange, emoji: "🌴", symbolName: .sunMaxFill)
        let newYork = RegionAppearance(color: .indigo, emoji: "🗽", symbolName: .building2Fill)
        try await session.services.setPrimaryRegions([
            PrimaryRegion(region: .california, appearance: california, order: 0),
            PrimaryRegion(region: .newYork, appearance: newYork, order: 1),
        ])

        let existing = try await session.services.primaryRegions()
        let model = PrimaryRegionSelectionModel(existing: existing)
        model.setEmoji("🌉", for: .california)
        try await model.commit(using: session)

        let saved = try await session.services.primaryRegions()
        #expect(saved.map(\.region) == [.california, .newYork])
        #expect(saved[0].appearance?.emoji == "🌉")
        #expect(saved[0].appearance?.color == california.color)
        #expect(saved[1].appearance == newYork)
    }

    @Test func editingDefaultsAddsAndReopensWithOntario() async throws {
        let session = PreviewSupport.loadedSession()
        let existing = try await session.services.primaryRegions()
        #expect(Set(existing.map(\.region)) == SwiftDataStore.defaultTrackedRegions)

        let ontario = try region("ca-ON")
        let model = PrimaryRegionSelectionModel(existing: existing)
        #expect(Set(model.selectedRegions) == [.california, .newYork])
        model.toggle(ontario)
        try await model.commit(using: session)

        let restored = try await session.services.primaryRegions()
        #expect(PrimaryRegionSelectionModel(existing: restored).selectedRegions == model
            .selectedRegions)
        #expect(try await session.services.trackedRegions() == [
            .california,
            .newYork,
            ontario,
        ])
    }

    @Test func committingAnEmptySelectionWipesExplicitPicks() async throws {
        // Regression guard for onboarding's restore path: committing an empty
        // selection *replaces* (deletes) the primary rows, so the store reverts
        // to the default set — i.e. the user's explicit (or just-restored) picks
        // are erased. Onboarding therefore must not commit after a restore; it
        // guards on `hasSelection`. This locks in the destructive behavior so the
        // reason for the guard stays explicit.
        let session = PreviewSupport.loadedSession()
        try await session.services.setPrimaryRegions([
            PrimaryRegion(
                region: .california,
                appearance: RegionAppearanceCatalog.defaultAppearance(for: .california),
                order: 0,
            ),
        ])
        #expect(try await session.services.trackedRegions() == [.california])

        let model = PrimaryRegionSelectionModel()
        #expect(!model.hasSelection)
        try await model.commit(using: session)

        // The explicit California pick is gone; with no rows, the store falls
        // back to the default set.
        #expect(try await session.services.trackedRegions() == SwiftDataStore.defaultTrackedRegions)
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
