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
            AboutSettingsView(
                focus: nil,
                buildInfo: PreviewSupport.stampedBuildInfo(),
                attribution: PreviewSupport.sampleAttribution(),
            )
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func hostsAnUnstampedBuild() throws {
        // The RegionViewer / test-host case: no version keys and no commit.
        let rootView = NavigationStack {
            AboutSettingsView(
                focus: nil,
                buildInfo: PreviewSupport.unstampedBuildInfo(),
                attribution: PreviewSupport.sampleAttribution(),
            )
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
            AboutSettingsView(
                focus: focus,
                buildInfo: PreviewSupport.stampedBuildInfo(),
                attribution: PreviewSupport.sampleAttribution(),
            )
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func hostsABundleCarryingNoReport() throws {
        // Every bundle but the app target's is in this state, so it has to render
        // rather than trip on a force-unwrapped manifest.
        let rootView = NavigationStack {
            AboutSettingsView(
                focus: nil,
                buildInfo: PreviewSupport.unstampedBuildInfo(),
                attribution: nil,
                dataSources: [],
            )
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func hostsAnEmptyReport() throws {
        let rootView = NavigationStack {
            AboutSettingsView(
                focus: nil,
                buildInfo: PreviewSupport.unstampedBuildInfo(),
                attribution: AttributionManifest(credits: []),
                dataSources: [],
            )
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func showsTheLiveDataSourceList() {
        // The screen shows what RegionKit vends, not a copy of its own. The
        // software credits are the app's generated report, asserted against the
        // real bundle in the Where app's `AppAttributionTests`.
        #expect(!RegionDataSource.all.isEmpty)
    }

    @Test func separatesLinkedLibrariesFromDevelopmentTools() {
        // The two kinds must reach the screen as distinct sections: a development
        // tool isn't in the binary, so listing it under "Open Source" alongside
        // the libraries would describe the running app inaccurately.
        let titles = Set(AboutSettingsView.Item.allCases.map(\.title))
        #expect(titles.contains(String(localized: .settingsAboutDevelopmentToolsHeader)))
        #expect(titles.contains(String(localized: .settingsAboutDependenciesHeader)))

        let sample = PreviewSupport.sampleAttribution()
        for kind in SoftwareCredit.Kind.allCases {
            #expect(
                !sample.credits(ofKind: kind).isEmpty,
                "the fixture credits nothing for \(kind), so that section goes untested",
            )
        }
    }
}
