import Foundation
import Testing
@testable import WhereCore

struct EncryptedBackupEnvelopeTests {
    @Test func cancelledCompressionDoesNotProduceAnArchive() throws {
        let service = BackupService()
        let progress = Progress(totalUnitCount: 0)
        progress.cancel()
        #expect(throws: (any Error).self) {
            try BackupService.$cancellationProgress.withValue(progress) {
                try service.makeArchiveFile(
                    samples: [],
                    evidence: [],
                    manualDays: [],
                    recordingDeviceProfiles: [],
                    recordingDeviceMetadataChanges: [],
                    recordingDeviceRemovals: [],
                    plannedStayRecords: [],
                    blobs: [:],
                    exportedAt: Date(),
                )
            }
        }
    }

    @Test func encryptedContainerRoundTripsAndWrongKeyIsRejected() throws {
        let service = BackupService()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
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
        defer { try? FileManager.default.removeItem(at: plaintext.deletingLastPathComponent()) }
        let key = try BackupRecoveryKey(data: Data(repeating: 42, count: 32))
        let encrypted = try service.makeEncryptedArchiveFile(
            from: plaintext,
            recoveryKey: key,
            exportedAt: date,
        )
        defer { try? FileManager.default.removeItem(at: encrypted.deletingLastPathComponent()) }

        let result = try service.readEncryptedArchive(at: encrypted, recoveryKey: key)
        #expect(result.archive.exportedAt == date)
        #expect(result.archive.formatVersion == BackupArchive.currentFormatVersion)

        let wrongKey = try BackupRecoveryKey(data: Data(repeating: 8, count: 32))
        #expect(throws: BackupService.EncryptedBackupError.recoveryKeyMismatch) {
            try service.readEncryptedArchive(at: encrypted, recoveryKey: wrongKey)
        }
    }
}
