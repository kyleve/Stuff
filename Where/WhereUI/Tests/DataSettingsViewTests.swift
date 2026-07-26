import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct DataSettingsViewTests {
    /// Reads the app model (reset sequence) from the environment.
    @Test func hosts() throws {
        let rootView = NavigationStack {
            DataSettingsView(report: PreviewSupport.loadedYearReportModel())
        }
        .environment(PreviewSupport.loadedModel())
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    /// A search deep-link hands the screen a focus token to scroll to + flash.
    @Test func hostsWithASearchFocus() throws {
        let focus = try #require(
            SettingsCatalog.results.first { $0.destination == .data },
        ).focus
        let rootView = NavigationStack {
            DataSettingsView(report: PreviewSupport.loadedYearReportModel(), focus: focus)
        }
        .environment(PreviewSupport.loadedModel())
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
