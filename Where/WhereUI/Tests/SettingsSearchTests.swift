import Testing
@testable import WhereUI

/// Covers the decentralized settings search index: that every group is
/// registered, tokens can't collide, and queries match on title and keywords.
@MainActor
struct SettingsSearchTests {
    @Test func everyDestinationIsRegistered() {
        let registered = Set(SettingsCatalog.results.map(\.destination))
        #expect(registered == Set(SettingsDestination.allCases))
    }

    @Test func everyDestinationAppearsInExactlyOneListSection() {
        let grouped = SettingsListSection.allCases.flatMap(\.destinations)
        // Full coverage, and no destination placed in two blocks.
        #expect(Set(grouped) == Set(SettingsDestination.allCases))
        #expect(grouped.count == SettingsDestination.allCases.count)
    }

    @Test func demoModeHidesOnlyTheGroupsThatReachPastIt() {
        let hidden = SettingsDestination.allCases.filter { !$0.isAvailableInDemoMode }
        // Data writes or restores an archive, erases, and resets; appearance
        // includes an app-icon setting that outlives the process. Everything else
        // is safe to explore, and the list would be a poor demo without it.
        #expect(Set(hidden) == [.data, .appearance])
    }

    @Test func focusTokensAreUnique() {
        let focuses = SettingsCatalog.results.map(\.focus)
        #expect(Set(focuses).count == focuses.count)
    }

    @Test func blankQueryMatchesNothing() {
        #expect(SettingsCatalog.results(matching: "").isEmpty)
        #expect(SettingsCatalog.results(matching: "   ").isEmpty)
    }

    @Test func matchesOnTitle() {
        let results = SettingsCatalog.results(matching: String(localized: .settingsBackupExport))
        #expect(results.contains { $0.destination == .data })
    }

    @Test func matchesOnKeyword() {
        // "gps" is a keyword for location tracking, data resolution, and the
        // Appearance dot toggle, but not part of their titles.
        let results = SettingsCatalog.results(matching: "gps")
        let destinations = Set(results.map(\.destination))
        #expect(destinations.contains(.location))
        #expect(destinations.contains(.alerts))
        #expect(destinations.contains(.appearance))
    }

    @Test func matchesTheAboutScreenOnALicenseKeyword() {
        // "license" is nowhere in a section title, so this only passes if the
        // About screen's keywords are registered.
        let results = SettingsCatalog.results(matching: "license")
        #expect(results.contains { $0.destination == .about })
    }

    @Test func focusedRouteCarriesTheResultsDestinationAndFocus() throws {
        let result = try #require(SettingsCatalog.results.first)
        let route = SettingsRoute(result)
        #expect(route.destination == result.destination)
        #expect(route.focus == result.focus)
    }

    @Test func groupRouteHasNoFocus() {
        #expect(SettingsRoute(.location).focus == nil)
    }
}
