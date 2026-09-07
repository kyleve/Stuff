import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct AutomaticBackupStorageTests {
    @Test func fallsBackToDocumentsAndRetainsTheNewestThree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "automatic-backup-storage-\(UUID().uuidString)",
                isDirectory: true,
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("local", isDirectory: true)
        let storage = AutomaticBackupStorage(
            iCloudRoot: { nil },
            localRoot: { local },
        )
        let service = BackupService()
        let key = try BackupRecoveryKey(data: Data(repeating: 42, count: 32))

        for day in 1 ... 4 {
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(day))
            let plaintext = try service.makeArchiveFile(
                samples: [],
                evidence: [],
                manualDays: [],
                recordingDeviceProfiles: [],
                recordingDeviceMetadataChanges: [],
                recordingDeviceRemovals: [],
                plannedStayRecords: [],
                blobs: [:],
                exportedAt: date,
            )
            let encrypted = try service.makeEncryptedArchiveFile(
                from: plaintext,
                recoveryKey: key,
                exportedAt: date,
            )
            _ = try await storage.store(encrypted)
            try? FileManager.default.removeItem(at: plaintext.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: encrypted.deletingLastPathComponent())
        }

        let manualFile = local.appendingPathComponent("manual.zip")
        try Data("manual".utf8).write(to: manualFile)
        let unrecognizedFile = local.appendingPathComponent("foreign.wherebackup")
        try Data("not a Where container".utf8).write(to: unrecognizedFile)
        let catalog = try await storage.catalog()

        #expect(catalog.isICloudUnavailable)
        #expect(catalog.files.count == 3)
        #expect(catalog.files.allSatisfy {
            $0.storageLocation == AutomaticBackupFile.StorageLocation.appDocuments
        })
        #expect(FileManager.default.fileExists(atPath: manualFile.path))
        #expect(FileManager.default.fileExists(atPath: unrecognizedFile.path))
    }
}
