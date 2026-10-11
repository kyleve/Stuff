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
        #expect(Set(hidden) == [.data, .appearance, .privacyDiagnostics])
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
        // "gps" is a keyword for device recording, data resolution, and the
        // Appearance dot toggle, but not part of their titles.
        let results = SettingsCatalog.results(matching: "gps")
        let destinations = Set(results.map(\.destination))
        #expect(destinations.contains(.devices))
        #expect(destinations.contains(.alerts))
        #expect(destinations.contains(.appearance))
    }

    @Test func matchesLocationForecastVisibilityOnEstimateKeyword() {
        let results = SettingsCatalog.results(matching: "estimate")

        #expect(results.contains {
            $0.destination == .appearance
                && $0.title == String(localized: .settingsAppearanceLocationForecastsToggle)
        })
    }

    @Test func matchesLocationWelcomeVisibilityOnGreetingKeyword() {
        let results = SettingsCatalog.results(matching: "greeting")

        #expect(results.contains {
            $0.destination == .appearance
                && $0.title == String(localized: .settingsAppearanceLocationWelcomeToggle)
        })
    }

    @Test func matchesTheRankingAnimationLabOnMotionKeyword() {
        let results = SettingsCatalog.results(matching: "overtake")

        #expect(results.contains {
            $0.destination == .appearance
                && $0.title == String(localized: .rankingAnimationTitle)
        })
    }

    @Test func matchesTheAboutScreenOnALicenseKeyword() {
        // "license" is nowhere in a section title, so this only passes if the
        // About screen's keywords are registered.
        let results = SettingsCatalog.results(matching: "license")
        #expect(results.contains { $0.destination == .about })
    }

    @Test func privacyDiagnosticsFollowsDataInTheSameBlock() {
        #expect(SettingsListSection.storage.destinations == [.data, .privacyDiagnostics])
    }

    @Test(arguments: ["crash", "session replay", "remote", "metadata"])
    func diagnosticChoicesAreSearchable(query: String) {
        let results = SettingsCatalog.results(matching: query)

        #expect(results.contains { $0.destination == .privacyDiagnostics })
    }

    @Test func matchesFeatureExplorersOnTheirPlatformKeywords() {
        let automation = SettingsCatalog.results(matching: "automation")
        let accessory = SettingsCatalog.results(matching: "accessory")
        let boardingPass = SettingsCatalog.results(matching: "boarding pass")
        let drift = SettingsCatalog.results(matching: "drift")
        let emoji = SettingsCatalog.results(matching: "emoji")
        let pace = SettingsCatalog.results(matching: "pace")
        #expect(automation.contains { $0.destination == .siri })
        #expect(accessory.contains { $0.destination == .widgets })
        #expect(boardingPass.contains { $0.destination == .shareEvidence })
        #expect(drift.contains { $0.destination == .insightsAccuracy })
        #expect(emoji.contains { $0.destination == .personalization })
        #expect(pace.contains { $0.destination == .estimatedTime })
    }

    @Test func estimatedTimePrecedesInsightsAndAccuracy() throws {
        let destinations = SettingsListSection.exploreFeatures.destinations
        let estimatedTime = try #require(destinations.firstIndex(of: .estimatedTime))
        let insights = try #require(destinations.firstIndex(of: .insightsAccuracy))

        #expect(estimatedTime < insights)
    }

    @Test func discoveryFollowsTheUserWorkflow() {
        #expect(SettingsListSection.exploreFeatures.destinations == [
            .placesYear,
            .recording,
            .estimatedTime,
            .insightsAccuracy,
            .shareEvidence,
            .siri,
            .widgets,
            .personalization,
            .privacyBackups,
        ])
        let availableInDemo = SettingsListSection.exploreFeatures.destinations
            .allSatisfy(\.isAvailableInDemoMode)
        #expect(availableInDemo)
    }

    @Test func newGuideSearchResultsFocusTheirOwningSection() throws {
        let timeline = try #require(SettingsCatalog.results(matching: "journey").first {
            $0.focus == SettingsFocus(PlacesYearFeaturesView.Item.timeline)
        })
        let manual = try #require(SettingsCatalog.results(matching: "manual").first {
            $0.destination == .recording
        })
        let restore = try #require(SettingsCatalog.results(matching: "restore").first {
            $0.destination == .privacyBackups
        })
        #expect(SettingsRoute(timeline).destination == .placesYear)
        #expect(SettingsRoute(timeline)
            .focus == SettingsFocus(PlacesYearFeaturesView.Item.timeline))
        #expect(SettingsRoute(manual).focus == SettingsFocus(RecordingFeaturesView.Item.manual))
        #expect(SettingsRoute(restore)
            .focus == SettingsFocus(PrivacyBackupsFeaturesView.Item.restore))
    }

    @Test func refreshedGuidesExposeTheirNewTopics() {
        #expect(SettingsCatalog.results(matching: "reminder")
            .contains { $0.destination == .insightsAccuracy })
        #expect(SettingsCatalog.results(matching: "theme")
            .contains { $0.destination == .personalization })
        #expect(SettingsCatalog.results(matching: "Timeline")
            .contains { $0.destination == .estimatedTime })
    }

    @Test func focusedRouteCarriesTheResultsDestinationAndFocus() throws {
        let result = try #require(SettingsCatalog.results.first)
        let route = SettingsRoute(result)
        #expect(route.destination == result.destination)
        #expect(route.focus == result.focus)
    }

    @Test func groupRouteHasNoFocus() {
        #expect(SettingsRoute(.devices).focus == nil)
    }
}
