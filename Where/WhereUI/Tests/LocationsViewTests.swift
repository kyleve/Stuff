import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

struct LocationsViewTests {
    @MainActor
    @Test func emptyLocationsCanAnimateTheirThemeBackground() throws {
        let theme = try activeThemeBackground()
        let host =
            UIHostingController(rootView: LocationsView(report: PreviewSupport
                    .emptyYearReportModel())
                .whereBroadwayRoot(themeDocument: theme)
                .environment(\.scenePhase, .active))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
        }
    }

    @Test func screenCompositionKeepsViewValuesWithinStackBudget() {
        #expect(MemoryLayout<LocationsView.Body>.size < 16384)
    }
}
