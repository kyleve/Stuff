import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct LocationSettingsViewTests {
    @Test func hostsWithASession() throws {
        let rootView = NavigationStack {
            LocationSettingsView(report: PreviewSupport.loadedYearReportModel())
        }
        .environment(PreviewSupport.loadedSession())
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
