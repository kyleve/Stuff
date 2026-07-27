import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct VisibleYearSettingsViewTests {
    @Test func hostsWithALoadedReport() throws {
        let rootView = NavigationStack {
            VisibleYearSettingsView(report: PreviewSupport.loadedYearReportModel())
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
