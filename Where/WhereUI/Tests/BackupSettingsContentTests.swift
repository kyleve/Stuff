import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct BackupSettingsContentTests {
    @Test func rehostingDisplayContentPreservesTheRevealedFixture() throws {
        let model = PreviewSupport.backupModel()
        let key = "VGhpcy1pcy1hLXNhbXBsZS1yZWNvdmVyeS1rZXku"
        model.configurePreview(
            catalogState: .loaded(AutomaticBackupCatalog(files: [], isICloudUnavailable: false)),
            recoveryKey: key,
        )
        for _ in 0 ..< 2 {
            let content = Form { BackupSettingsContent(backup: model, recordingEnabled: true) }
            try show(UIHostingController(rootView: content)) { hosted in
                #expect(hosted.view != nil)
            }
            #expect(model.revealedRecoveryKey == key)
        }
    }
}
