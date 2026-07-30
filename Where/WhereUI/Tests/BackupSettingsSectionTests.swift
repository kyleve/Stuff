import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct BackupSettingsSectionTests {
    @Test func hostsWithABackupModel() throws {
        let rootView = Form {
            BackupSettingsSection(backup: PreviewSupport.backupModel())
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
