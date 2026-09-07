import Foundation
@_spi(Testing) import KeychainKit
@_spi(Testing) @testable import WhereCore

actor BackupAccessGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var hasArrived = false
    private var isOpen = false

    func wait() async -> Bool {
        if isOpen { return true }
        hasArrived = true
        arrival?.resume()
        arrival = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitForArrival() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        isOpen = true
        continuation?.resume(returning: true)
        continuation = nil
    }
}

struct AutomaticBackupStorageFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key: BackupRecoveryKey
    let keys: BackupRecoveryKeyProvider

    init() throws {
        key = try BackupRecoveryKey(data: Data(repeating: 51, count: 32))
        keys = BackupRecoveryKeyProvider(store: InMemoryKeychainStore(data: key.data)) { true }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeArchive(at date: Date) throws -> URL {
        let service = BackupService()
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
        return try service.makeEncryptedArchiveFile(
            from: plaintext,
            recoveryKey: key,
            exportedAt: date,
        )
    }

    func cleanup() throws {
        try FileManager.default.removeItem(at: root)
    }
}

actor GatedAutomaticBackupScheduler: AutomaticBackupTaskScheduling {
    enum Event: Equatable {
        case reconciled(Bool)
        case shutDown
    }

    let gate: BackupAccessGate
    private(set) var events: [Event] = []

    init(gate: BackupAccessGate) {
        self.gate = gate
    }

    func reconcile(isEnabled: Bool, earliestBeginDate _: Date?) async {
        events.append(.reconciled(isEnabled))
        if events.count == 1 { _ = await gate.wait() }
    }

    func didShutDown() {
        events.append(.shutDown)
    }
}
