import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct BackupSettingsViewTests {
    @Test func hostsWithABackupModel() throws {
        let rootView = NavigationStack {
            BackupSettingsView(backup: PreviewSupport.backupModel())
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
