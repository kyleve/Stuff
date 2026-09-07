import Foundation
@_spi(Testing) import KeychainKit
import Testing
@_spi(Testing) @testable import WhereCore

struct AutomaticBackupServiceTests {
    @Test func shutdownDrainsAnInFlightScheduleBeforeReturning() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let gate = BackupAccessGate()
        let scheduler = GatedAutomaticBackupScheduler(gate: gate)
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: fixture.keys,
            automaticBackupStorage: AutomaticBackupStorage(
                iCloudRoot: { nil },
                localRoot: { fixture.root },
            ),
            automaticBackupScheduler: scheduler,
        )
        let automatic = try #require(services.automaticBackups)
        let initial = Task {
            await automatic.reconcileSchedule(configuration: .init(
                isEnabled: true,
                isRecordingEnabled: true,
                interval: .weekly,
                lastSuccessfulBackupAt: nil,
            ))
        }
        await gate.waitForArrival()
        let shutdown = Task {
            await automatic.shutDown()
            await scheduler.didShutDown()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await !automatic.isRetiredForTesting, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(await automatic.isRetiredForTesting)
        await gate.release()
        await initial.value
        await shutdown.value
        #expect(await scheduler.events == [.reconciled(true), .reconciled(false), .shutDown])
    }

    @Test func intervalChangeDuringExportUsesTheNewIntervalAfterSuccess() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let gate = BackupAccessGate()
        let scheduler = SpyAutomaticBackupScheduler()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: BackupRecoveryKeyProvider(
                store: InMemoryKeychainStore(),
                isProtectedDataAvailable: { await gate.wait() },
            ),
            automaticBackupStorage: AutomaticBackupStorage(
                iCloudRoot: { nil },
                localRoot: { fixture.root },
            ),
            automaticBackupScheduler: scheduler,
            now: { now },
        )
        let automatic = try #require(services.automaticBackups)
        let operation = Task {
            try await automatic.runIfDue(configuration: .init(
                isEnabled: true,
                isRecordingEnabled: true,
                interval: .weekly,
                lastSuccessfulBackupAt: nil,
            ))
        }
        await gate.waitForArrival()
        await automatic.reconcileSchedule(configuration: .init(
            isEnabled: true,
            isRecordingEnabled: true,
            interval: .monthly,
            lastSuccessfulBackupAt: nil,
        ))
        await gate.release()
        #expect(try await operation.value == .completed(exportedAt: now))
        #expect(await scheduler.latest?.earliestBeginDate == AutomaticBackupInterval.monthly
            .nextDate(after: now))
    }

    @Test func suspensionCanResumeButRetiredScopesCannotExportOrSchedule() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let scheduler = SpyAutomaticBackupScheduler()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: fixture.keys,
            automaticBackupStorage: AutomaticBackupStorage(
                iCloudRoot: { nil },
                localRoot: { fixture.root },
            ),
            automaticBackupScheduler: scheduler,
        )
        let automatic = try #require(services.automaticBackups)
        let configuration = AutomaticBackupConfiguration(
            isEnabled: true,
            isRecordingEnabled: true,
            interval: .weekly,
            lastSuccessfulBackupAt: nil,
        )
        await automatic.reconcileSchedule(configuration: configuration)
        await automatic.suspend()
        #expect(await scheduler.latest?.isEnabled == false)
        #expect(try await automatic.runIfDue(configuration: configuration) == .disabled)
        await automatic.resume()
        #expect(await scheduler.latest?.isEnabled == true)
        await automatic.shutDown()
        await automatic.resume()
        #expect(try await automatic.runIfDue(configuration: configuration) == .disabled)
        #expect(await scheduler.latest?.isEnabled == false)
        #expect(try await automatic.catalog().files.isEmpty)
    }

    @Test func disablingDuringKeyAccessCancelsTheExportAndKeepsSchedulingDisabled() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let gate = BackupAccessGate()
        let scheduler = SpyAutomaticBackupScheduler()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: BackupRecoveryKeyProvider(
                store: InMemoryKeychainStore(),
                isProtectedDataAvailable: { await gate.wait() },
            ),
            automaticBackupStorage: AutomaticBackupStorage(
                iCloudRoot: { nil },
                localRoot: { fixture.root },
            ),
            automaticBackupScheduler: scheduler,
        )
        let automatic = try #require(services.automaticBackups)
        let operation = Task {
            try await automatic.runIfDue(configuration: .init(
                isEnabled: true,
                isRecordingEnabled: true,
                interval: .weekly,
                lastSuccessfulBackupAt: nil,
            ))
        }
        await gate.waitForArrival()
        await automatic.reconcileSchedule(configuration: .init(
            isEnabled: false,
            isRecordingEnabled: true,
            interval: .monthly,
            lastSuccessfulBackupAt: nil,
        ))
        await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await scheduler.latest?.isEnabled == false)
        #expect(try await automatic.catalog().files.isEmpty)
    }

    @Test func expirationCancelsTheOwnedOperationWithoutRecordingSuccess() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let gate = BackupAccessGate()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            backupRecoveryKeys: BackupRecoveryKeyProvider(
                store: InMemoryKeychainStore(),
                isProtectedDataAvailable: { await gate.wait() },
            ),
            automaticBackupStorage: AutomaticBackupStorage(
                iCloudRoot: { nil },
                localRoot: { fixture.root },
            ),
        )
        let automatic = try #require(services.automaticBackups)
        let operation = Task {
            try await automatic.runIfDue(configuration: .init(
                isEnabled: true,
                isRecordingEnabled: true,
                interval: .weekly,
                lastSuccessfulBackupAt: nil,
            ))
        }
        await gate.waitForArrival()
        operation.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try await automatic.catalog().files.isEmpty)
    }

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
        // A caller's stale preference snapshot must not produce another file.
        #expect(try await automatic
            .runIfDue(configuration: configuration) == .notDue(nextEligibleAt: next))
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
