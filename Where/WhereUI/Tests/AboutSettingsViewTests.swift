import CreditKit
import Foundation
import Testing
@testable import WhereUI

/// Covers Settings placement, search registration, and attribution content states.
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
        for query in ["licenses", "sha", "geojson", "skills", "github", "repository"] {
            let destinations = Set(SettingsCatalog.results(matching: query).map(\.destination))
            #expect(destinations.contains(.about), "no About result for \"\(query)\"")
        }
    }

    // MARK: Attribution content

    @Test func distinguishesAnAbsentReportFromAnEmptySection() {
        // The two say different things about the build: no report means nothing
        // is attributed at all, while an empty section of a real report means
        // only that this one kind is unpopulated.
        let absent = AboutSettingsView(focus: nil, attribution: nil, dataSources: [])
        #expect(
            String(localized: absent.emptyMessage)
                == String(localized: .settingsAboutAttributionUnavailable),
        )

        let empty = AboutSettingsView(
            focus: nil,
            attribution: AttributionManifest(credits: []),
            dataSources: [],
        )
        #expect(
            String(localized: empty.emptyMessage)
                == String(localized: .settingsAboutAttributionNone),
        )
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
