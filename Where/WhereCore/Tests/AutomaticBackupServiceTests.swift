import Foundation
@_spi(Testing) import KeychainKit
import Testing
@_spi(Testing) @testable import WhereCore

struct AutomaticBackupServiceTests {
    @Test func firstRunIsImmediateAndTheNextRunUsesTheLastSuccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "automatic-backup-service-\(UUID().uuidString)",
                isDirectory: true,
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = SpyAutomaticBackupScheduler()
        let keys = BackupRecoveryKeyProvider(store: InMemoryKeychainStore()) { true }
        let storage = AutomaticBackupStorage(
            iCloudRoot: { nil },
            localRoot: { root },
        )
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: keys,
            automaticBackupStorage: storage,
            automaticBackupScheduler: scheduler,
            now: { now },
        )
        let automatic = try #require(services.automaticBackups)
        let configuration = AutomaticBackupConfiguration(
            isEnabled: true,
            isRecordingEnabled: true,
            interval: .weekly,
            lastSuccessfulBackupAt: nil,
        )

        #expect(try await automatic.runIfDue(configuration: configuration) == .completed(
            exportedAt: now,
        ))
        let catalog = try await automatic.catalog()
        #expect(catalog.files.count == 1)

        let afterSuccess = AutomaticBackupConfiguration(
            isEnabled: true,
            isRecordingEnabled: true,
            interval: .weekly,
            lastSuccessfulBackupAt: now,
        )
        let next = AutomaticBackupInterval.weekly.nextDate(after: now)
        #expect(try await automatic.runIfDue(configuration: afterSuccess) == .notDue(
            nextEligibleAt: next,
        ))
        #expect(await scheduler.latest?.isEnabled == true)
    }

    @Test func lockedKeyDefersBeforeExport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "automatic-backup-locked-\(UUID().uuidString)",
                isDirectory: true,
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: BackupRecoveryKeyProvider(
                store: InMemoryKeychainStore(data: Data(repeating: 1, count: 32)),
                isProtectedDataAvailable: { false },
            ),
            automaticBackupStorage: AutomaticBackupStorage(
                iCloudRoot: { nil },
                localRoot: { root },
            ),
        )
        let automatic = try #require(services.automaticBackups)

        #expect(try await automatic.runIfDue(configuration: .init(
            isEnabled: true,
            isRecordingEnabled: true,
            interval: .weekly,
            lastSuccessfulBackupAt: nil,
        )) == .deferredUntilFirstUnlock)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

private actor SpyAutomaticBackupScheduler: AutomaticBackupTaskScheduling {
    struct Reconciliation {
        let isEnabled: Bool
        let earliestBeginDate: Date?
    }

    private(set) var latest: Reconciliation?

    func reconcile(isEnabled: Bool, earliestBeginDate: Date?) {
        latest = Reconciliation(isEnabled: isEnabled, earliestBeginDate: earliestBeginDate)
    }
}
