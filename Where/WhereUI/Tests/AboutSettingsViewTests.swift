import CreditKit
import RegionKit
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Covers the About screen's registration in Settings search and that it renders
/// each build-metadata state — including the unstamped one, which is what every
/// bundle other than the shipping app produces.
@MainActor
struct AboutSettingsViewTests {
    // MARK: Placement

    @Test func aboutIsTheLastBlockInTheSettingsList() throws {
        let last = try #require(SettingsListSection.allCases.last)
        #expect(last.destinations == [.about])
    }

    @Test func aboutPushesRatherThanPresentingASheet() {
        #expect(!SettingsDestination.about.isSheet)
    }

    // MARK: Search

    @Test func everyItemIsRegisteredForSearch() {
        let registered = AboutSettingsView.searchResults
        #expect(registered.count == AboutSettingsView.Item.allCases.count)
        #expect(registered.allSatisfy { $0.destination == .about })
    }

    @Test func searchFindsTheAboutSettingsByKeyword() {
        // None of these words appear in the section titles, so a match proves the
        // keyword lists are wired rather than the titles happening to overlap.
        for query in ["licenses", "sha", "geojson", "skills"] {
            let destinations = Set(SettingsCatalog.results(matching: query).map(\.destination))
            #expect(destinations.contains(.about), "no About result for \"\(query)\"")
        }
    }

    // MARK: Rendering

    @Test func hostsAStampedBuild() throws {
        let rootView = NavigationStack {
            AboutSettingsView(focus: nil, buildInfo: PreviewSupport.stampedBuildInfo())
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func hostsAnUnstampedBuild() throws {
        // The RegionViewer / test-host case: no version keys and no commit.
        let rootView = NavigationStack {
            AboutSettingsView(focus: nil, buildInfo: PreviewSupport.unstampedBuildInfo())
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func hostsWithASearchFocus() throws {
        let focus = try #require(
            SettingsCatalog.results.first { $0.destination == .about },
        ).focus
        let rootView = NavigationStack {
            AboutSettingsView(focus: focus, buildInfo: PreviewSupport.stampedBuildInfo())
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func hostsWithNothingToCredit() throws {
        // Defensive: an empty credit list must render empty sections rather than
        // trip on a force-unwrapped "first" credit.
        let rootView = NavigationStack {
            AboutSettingsView(
                focus: nil,
                buildInfo: PreviewSupport.unstampedBuildInfo(),
                credits: [],
                dataSources: [],
            )
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func creditsTheLiveDependencyAndDataSourceLists() {
        // The screen shows what the owning modules vend, not a copy of its own.
        #expect(!CreditCatalog.shared.credits.isEmpty)
        #expect(!RegionDataSource.all.isEmpty)
    }

    @Test func separatesLinkedLibrariesFromDevelopmentTools() {
        // The two kinds must reach the screen as distinct sections: a development
        // tool isn't in the binary, so listing it under "Open Source" alongside
        // the libraries would describe the running app inaccurately.
        for kind in SoftwareCredit.Kind.allCases {
            #expect(
                !CreditCatalog.shared.credits(ofKind: kind).isEmpty,
                "nothing credited for \(kind), so the section would render empty",
            )
        }
        let titles = Set(AboutSettingsView.Item.allCases.map(\.title))
        #expect(titles.contains(String(localized: .settingsAboutDevelopmentToolsHeader)))
        #expect(titles.contains(String(localized: .settingsAboutDependenciesHeader)))
    }
}
