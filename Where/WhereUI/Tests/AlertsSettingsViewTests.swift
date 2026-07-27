import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct AlertsSettingsViewTests {
    @Test func hostsWithReminders() throws {
        let rootView = NavigationStack {
            AlertsSettingsView(
                report: PreviewSupport.loadedYearReportModel(),
                reminders: PreviewSupport.remindersSettingsModel(),
            )
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
