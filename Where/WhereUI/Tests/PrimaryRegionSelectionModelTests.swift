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
        let groups = model.browse(expandedCountries: []).countryGroups
        #expect(groups.map { $0.country?.id.rawValue } == [
            "united-states",
            "canada",
            nil,
        ])
        #expect(groups.map(\.regions) == [
            [.newYork, .california],
            [.ontario],
            [.other, .europeanUnion],
        ])
    }

    @Test func countriesWithOnlyYearShortcutsStayBrowsable() throws {
        let quebec = try region("ca-QC")
        let model = PrimaryRegionSelectionModel(available: [.ontario, .newYork, quebec, .other])
        model.applyGrouping(usedThisYear: Set(model.available))
        let collapsed = model.browse(expandedCountries: [])
        #expect(collapsed.usedThisYear == [.ontario, .newYork, quebec])
        #expect(collapsed.countryGroups.map(\.regions) == [
            [.ontario, quebec],
            [.newYork],
            [.other],
        ])

        let canada: RegionCatalog.Node.ID = .init(rawValue: "canada")
        let expanded = model.browse(expandedCountries: [canada])
        #expect(expanded.usedThisYear == [.newYork])
        #expect(expanded.countryGroups.map(\.regions) == collapsed.countryGroups.map(\.regions))
    }

    @Test func postalCodePrecedesOtherNameMatchesAcrossCountries() throws {
        let washington = try region("us-WA")
        let model = PrimaryRegionSelectionModel(available: [washington, .ontario, .newYork])
        model.toggle(.newYork)
        model.searchText = "  oN\n"
        #expect(model.searchResults == .available([.ontario, washington]))
        model.toggle(.ontario)
        #expect(model.searchResults == .available([washington]))
        model.searchText = "ny"
        #expect(model.searchResults == .allSelected)
        model.toggle(.newYork)
        #expect(model.searchResults == .available([.newYork]))
        model.searchText = "alaska"
        #expect(model.searchResults == .noMatches)
        model.searchText = "  \n"
        #expect(model.isSearching == false)
    }

    @Test func searchMatchesAccentsInLocalizedNames() throws {
        let quebec = try region("ca-QC")
        let model = PrimaryRegionSelectionModel()
        model.searchText = "québ"
        #expect(model.searchResults == .available([quebec]))
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
                try await tap(region.localizedName, in: controller.view)
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
        let picker = NavigationStack {
            RegionPickerView(model: model)
                .navigationTitle(String(localized: .onboardingRegionsTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .onboardingNext)) {}
                            .disabled(!model.hasSelection)
                    }
                }
        }.whereBroadwayRoot()
        let host = UIHostingController(rootView: Optional(picker))
        try await show(host) { controller in
            let view = try #require(controller.view)
            view.window?.layer.speed = 1
            defer { endSearch(in: view) }
            try await tap(canada.localizedName, in: view)
            try await tap(Region.ontario.localizedName, in: view)
            try await waitForAsync { model.selectedRegions == [.ontario] }

            let field = try await focusBottomSearch(in: controller)
            field.insertText("NY")
            try await waitForAsync {
                button(Region.newYork.localizedName, in: view)?.accessibilityValue == "US · NY"
            }
            try await tap(Region.newYork.localizedName, in: view)
            try await waitForAsync {
                guard let newest = button(Region.newYork.localizedName, in: view),
                      let first = button(Region.ontario.localizedName, in: view),
                      newest.accessibilityTraits.contains(.selected),
                      first.accessibilityTraits.contains(.selected)
                else { return false }
                return newest.accessibilityFrame.midY < first.accessibilityFrame.midY
            }
            #expect(model.selectedRegions == [.ontario, .newYork])
            try await tap(Region.ontario.localizedName, in: view)
            try await waitForAsync { model.selectedRegions == [.newYork] }

            field.selectAll(nil)
            field.deleteBackward()
            try await waitForAsync {
                button(Region.ontario.localizedName, in: view)?.accessibilityValue == "ON"
            }
            #expect(model.searchText.isEmpty)
            #expect(field.isFirstResponder)
            field.insertText("NY")
            try await waitForAsync { model.searchText == "NY" }
            // Onboarding replaces the picker when advancing and reuses the draft when returning.
            host.rootView = nil
            try await waitForAsync { model.searchText.isEmpty && !field.isFirstResponder }
            host.rootView = picker
            try await waitForAsync {
                button(Region.newYork.localizedName, in: view)?.accessibilityTraits
                    .contains(.selected) == true
            }
            #expect(model.selectedRegions == [.newYork])
        }
    }

    @Test func settingsManageShowsNativeBottomSearchInItsPresentedNavigationStack() async throws {
        let session = PreviewSupport.loadedSession()
        let sheet = UIHostingController(rootView: RegionsSettingsView()
            .environment(session)
            .whereBroadwayRoot())
        sheet.modalPresentationStyle = .pageSheet
        try await show(UIViewController()) { presenter in
            presenter.view.window?.layer.speed = 1
            presenter.present(sheet, animated: false)
            defer {
                endSearch(in: sheet.view)
                sheet.presentingViewController?.dismiss(animated: false)
            }
            try await tap(String(localized: .settingsRegionsManage), in: sheet.view)
            let field = try await focusBottomSearch(in: sheet)
            field.insertText("ON")
            try await waitForAsync {
                button(Region.ontario.localizedName, in: sheet.view)?.accessibilityValue == "CA · ON"
            }
        }
    }

    private func button(_ label: String, in view: UIView) -> NSObject? {
        HostedAccessibility.objects(in: view).first {
            $0.accessibilityTraits.contains(.button)
                && $0.accessibilityLabel?.hasPrefix(label) == true
        }
    }

    private func tap(_ label: String, in view: UIView) async throws {
        do { try await waitForAsync { button(label, in: view) != nil } }
        catch { throw TestHostError("Missing button \(label): \(error)") }
        let element = try #require(button(label, in: view))
        if let control = element as? UIControl {
            control.sendActions(for: .touchUpInside)
        } else {
            try #require(element.accessibilityActivate(), "Activate \(label)")
        }
    }

    private func endSearch(in view: UIView) {
        view.window?.endEditing(true)
        for bar in AdaptivePaneTestSupport.descendants(of: view, matching: UINavigationBar.self) {
            bar.topItem?.searchController?.isActive = false
        }
    }

    private func focusBottomSearch(in controller: UIViewController) async throws
        -> UISearchTextField
    {
        let view = try #require(controller.view)
        let window = try #require(view.window)
        @MainActor func isSettled(_ controller: UIViewController) -> Bool {
            !controller.isBeingPresented && controller.transitionCoordinator == nil
                && controller.children.allSatisfy(isSettled)
        }
        @MainActor func visibleField() -> UISearchTextField? {
            AdaptivePaneTestSupport.descendants(of: view, matching: UISearchTextField.self)
                .first { field in
                    var ancestor: UIView? = field
                    while let current = ancestor {
                        if current.isHidden || current.alpha == 0 { return false }
                        ancestor = current.superview
                    }
                    let frame = field.convert(field.bounds, to: view)
                    return field.window != nil && frame.width > 2 * frame.height &&
                        frame.height > 0 && view.bounds.contains(frame)
                }
        }
        try await waitForAsync { isSettled(controller) && visibleField() != nil }
        let field = try #require(visibleField())
        #expect(field.convert(field.bounds, to: view).midY > view.bounds.midY)
        let navigationBars = AdaptivePaneTestSupport.descendants(
            of: view,
            matching: UINavigationBar.self,
        )
        let searchControllers = navigationBars.compactMap { $0.topItem?.searchController }
        let search = try #require(searchControllers.first)
        search.isActive = true
        @MainActor func focusedField() -> UISearchTextField? {
            AdaptivePaneTestSupport.descendants(of: window, matching: UISearchTextField.self)
                .first(where: \.isFirstResponder)
        }
        // A toolbar can host a presentation copy. UIKit's search bar forwards focus to the editor.
        try await waitForAsync {
            if focusedField() != nil { return true }
            _ = search.searchBar.becomeFirstResponder()
            return focusedField() != nil
        }
        // Focus can transfer before the system field has finished moving above the keyboard.
        try await waitForAsync {
            guard let editor = focusedField(), !search.isBeingPresented,
                  search.transitionCoordinator == nil else { return false }
            let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
            let frame = editor.convert(editor.bounds, to: view)
            return frame.maxY <= keyboardTop && keyboardTop - frame.maxY < frame.height * 2
        }
        return try #require(focusedField())
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
        model.toggle(picks[0])
        model.toggle(extra)
        #expect(model.selectedNewestFirst.first == extra)
        #expect(model.desiredPrimaryRegions.map(\.region) == Array(picks.dropFirst()) + [extra])
    }

    @Test func mergedPicksBeyondTheCapStayFindableAndSurviveSaving() async throws {
        let cap = PrimaryRegionSelectionModel.maxSelection
        let available = Array(PrimaryRegionSelectionModel.supportedRegions.prefix(cap + 3))
        let merged = Array(available.prefix(cap + 2))
        let extra = available[cap + 2]
        let model = PrimaryRegionSelectionModel(
            existing: merged.enumerated()
                .map { PrimaryRegion(region: $1, appearance: nil, order: $0) },
            available: available,
        )
        let session = PreviewSupport.loadedSession()
        try await model.commit(using: session)
        #expect(try await session.services.primaryRegions().map(\.region) == merged)
        #expect(model.selectedNewestFirst == Array(merged.suffix(cap).reversed()))
        #expect(model.selectionCount == merged.count)

        let first = merged[0], second = merged[1]
        model.applyGrouping(usedThisYear: [first])
        let collapsed = model.browse(expandedCountries: [])
        #expect(collapsed.usedThisYear == [first])
        #expect(collapsed.countryGroups.flatMap(\.regions) == [first, second, extra])
        let expanded = model.browse(expandedCountries: [.init(rawValue: "united-states")])
        #expect(expanded.usedThisYear.isEmpty)
        #expect(expanded.countryGroups.flatMap(\.regions) == [first, second, extra])
        model.searchText = first.localizedName
        #expect(model.searchResults == .available([first]))
        #expect(model.isSelected(first))
        model.toggle(first)
        #expect(model.selectionCount == cap + 1)
        #expect(model.isSelected(first) == false)
        #expect(model.canToggle(extra) == false)

        model.toggle(merged[cap + 1])
        #expect(model.selectionCount == cap)
        #expect(model.selectedNewestFirst.last == second)
        model.searchText = second.localizedName
        #expect(model.searchResults == .allSelected)
        #expect(model.canToggle(extra) == false)
        model.toggle(second)
        #expect(model.canToggle(extra))
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

    @Test func selectedRegionsMoveBetweenTheTopYearShortcutsAndCountries() throws {
        let texas = try region("us-TX")
        let florida = try region("us-FL")
        let model = PrimaryRegionSelectionModel(
            existing: [PrimaryRegion(region: .california, appearance: nil, order: 0)],
            available: [.california, .newYork, texas, florida],
        )
        model.applyGrouping(usedThisYear: [.newYork, .california])

        #expect(model.isGrouped)
        #expect(model.selectedNewestFirst == [.california])
        let initial = model.browse(expandedCountries: [])
        #expect(initial.usedThisYear == [.newYork])
        #expect(initial.countryGroups.flatMap(\.regions) == [.newYork, texas, florida])

        model.toggle(.newYork)
        model.toggle(texas)
        #expect(model.selectedNewestFirst == [texas, .newYork, .california])
        let afterAdditions = model.browse(expandedCountries: [])
        #expect(afterAdditions.usedThisYear.isEmpty)
        #expect(afterAdditions.countryGroups.flatMap(\.regions) == [florida])
        #expect(model.desiredPrimaryRegions.map(\.region) == [.california, .newYork, texas])

        model.toggle(.california)
        model.toggle(texas)
        #expect(model.selectedNewestFirst == [.newYork])
        let afterRemovals = model.browse(expandedCountries: [])
        #expect(afterRemovals.usedThisYear == [.california])
        #expect(afterRemovals.countryGroups.flatMap(\.regions) == [.california, texas, florida])
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
