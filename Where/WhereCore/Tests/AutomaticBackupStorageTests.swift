import Foundation
@_spi(Testing) import KeychainKit
import Testing
import ZIPFoundation
@_spi(Testing) @testable import WhereCore

struct AutomaticBackupStorageTests {
    @Test(.timeLimit(.minutes(1)))
    func blockedCatalogDoesNotOwnTheStorageActorAndReceivesCancellation() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let blockedURL = fixture.root.appendingPathComponent("blocked.wherebackup")
        try Data([1]).write(to: blockedURL)
        let availability = BlockingBackupFileAvailability(blockedURL: blockedURL)
        defer { availability.release() }
        let storage = AutomaticBackupStorage(
            iCloudRoot: { fixture.root },
            localRoot: { fixture.root.appendingPathComponent("local") },
            availability: availability,
        )
        let read = Task { try await storage.catalog() }
        defer { read.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !availability.hasArrived, ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(availability.hasArrived)
        let source = try fixture.makeArchive(at: Date(timeIntervalSince1970: 1))
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let stored = try await storage.store(source)
        #expect(FileManager.default.fileExists(atPath: stored.url.path))
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
    }

    @Test func evictedCloudFilesDoNotHideAccessibleCloudAndLocalBackups() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let cloud = fixture.root.appendingPathComponent("cloud")
        let local = fixture.root.appendingPathComponent("local")
        let writer = AutomaticBackupStorage(iCloudRoot: { cloud }, localRoot: { local })
        let localWriter = AutomaticBackupStorage(iCloudRoot: { nil }, localRoot: { local })
        let cloudSource = try fixture.makeArchive(at: Date(timeIntervalSince1970: 2))
        defer { try? FileManager.default.removeItem(at: cloudSource.deletingLastPathComponent()) }
        let localSource = try fixture.makeArchive(at: Date(timeIntervalSince1970: 1))
        defer { try? FileManager.default.removeItem(at: localSource.deletingLastPathComponent()) }
        let cloudFile = try await writer.store(cloudSource)
        let localFile = try await localWriter.store(localSource)
        let evicted = cloud.appendingPathComponent("evicted.wherebackup")
        // Unreadable contents deliberately fail if the preflight is performed
        // after content access. No real iCloud account is used by this test.
        try FileManager.default.createDirectory(at: evicted, withIntermediateDirectories: true)
        let reader = AutomaticBackupStorage(
            iCloudRoot: { cloud },
            localRoot: { local },
            availability: ScriptedBackupFileAvailability(unavailable: [evicted]),
        )
        let catalog = try await reader.catalog()
        #expect(catalog.isICloudUnavailable)
        #expect(catalog.files.map(\.url) == [cloudFile.url, localFile.url])
    }

    @Test func cancelledCatalogIsNotReportedAsAnEmptyOrPartialSuccess() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let storage = AutomaticBackupStorage(iCloudRoot: { nil }, localRoot: { fixture.root })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await storage.catalog()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func forgedFutureEnvelopesCannotDisplaceRecoverableBackups() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let local = fixture.root.appendingPathComponent("local")
        let storage = AutomaticBackupStorage(iCloudRoot: { nil }, localRoot: { local })
        var validFiles: [URL] = []
        for index in 0 ..< 3 {
            let archive = try fixture.makeArchive(at: Date(timeIntervalSince1970: Double(index)))
            defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
            try await validFiles.append(storage.store(archive).url)
        }
        // Valid-looking metadata, but there is no authenticated payload.
        let contents = fixture.root.appendingPathComponent("forged")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        for index in 0 ..< 3 {
            let envelope = EncryptedBackupEnvelope(
                keyIdentifier: fixture.key.identifier,
                exportedAt: Date(timeIntervalSince1970: 2_000_000_000 + Double(index)),
            )
            try BackupService.makeEncoder().encode(envelope)
                .write(to: contents.appendingPathComponent("envelope.json"))
            try FileManager.default.zipItem(
                at: contents,
                to: local.appendingPathComponent("forged-\(index).wherebackup"),
                shouldKeepParent: false,
            )
        }
        try await storage.reconcileRetention(recoveryKeys: fixture.keys)
        #expect(validFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(try await storage.catalog().files.count == 6)
    }

    @Test func cloudCommitIsNotRetriedLocallyWhenRetentionCannotEnumerateLocalStorage(
    ) async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let cloud = fixture.root.appendingPathComponent("cloud")
        let local = fixture.root.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: local)
        let storage = AutomaticBackupStorage(iCloudRoot: { cloud }, localRoot: { local })
        let archive = try fixture.makeArchive(at: Date())
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let stored = try await storage.store(archive)
        #expect(stored.storageLocation == .iCloudDrive)
        await #expect(throws: (any Error).self) {
            try await storage.reconcileRetention(recoveryKeys: fixture.keys)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: cloud.path).count == 1)
        #expect(try Data(contentsOf: local) == Data([1]))
    }

    @Test func catalogReportsCloudFailureAndThrowsForLocalFailure() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let invalid = fixture.root.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: invalid)
        let partial = AutomaticBackupStorage(
            iCloudRoot: { invalid },
            localRoot: { fixture.root.appendingPathComponent("empty") },
        )
        #expect(try await partial.catalog().isICloudUnavailable)
        let failed = AutomaticBackupStorage(iCloudRoot: { nil }, localRoot: { invalid })
        await #expect(throws: (any Error).self) { try await failed.catalog() }
    }

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
        let keys = BackupRecoveryKeyProvider(store: InMemoryKeychainStore(data: key.data)) { true }

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
            try await storage.reconcileRetention(recoveryKeys: keys)
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
