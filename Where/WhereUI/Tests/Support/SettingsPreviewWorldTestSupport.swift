#if DEBUG
    import Foundation
    import Testing
    import WhereCore
    @testable import WhereUI

    @MainActor
    enum SettingsPreviewWorldTestSupport {
        /// Reads the exported values and returns the coordinator's temporary files immediately.
        static func exportArchive(using backup: BackupModel) async throws -> BackupArchive {
            let url = try #require(await backup.exportBackup())
            do {
                let archive = try BackupService().readArchive(at: url).archive
                await backup.discardExport()
                #expect(FileManager.default.fileExists(atPath: url.path) == false)
                return archive
            } catch {
                await backup.discardExport()
                throw error
            }
        }
    }
#endif
