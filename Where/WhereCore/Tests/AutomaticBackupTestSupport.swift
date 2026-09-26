import CryptoKit
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

    func makeVerifiedFiles(count: Int) async throws -> [AutomaticBackupRetention.VerifiedFile] {
        let storage = AutomaticBackupStorage(iCloudRoot: { nil }, localRoot: { root })
        var verified: [AutomaticBackupRetention.VerifiedFile] = []
        for index in 0 ..< count {
            let date = Date(timeIntervalSince1970: Double(index))
            let source = try makeArchive(at: date)
            defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
            let file = try await storage.store(source)
            _ = try BackupService().readEncryptedArchive(at: file.url, recoveryKey: key)
            try verified.append(AutomaticBackupRetention.VerifiedFile(
                file: file,
                digest: SHA256.hash(data: Data(contentsOf: file.url)),
                exportedAt: date,
            ))
        }
        return verified
    }
}

struct ScriptedBackupFileAvailability: AutomaticBackupFileAvailabilityChecking {
    let unavailable: Set<URL>

    func isDownloaded(at url: URL) throws -> Bool {
        !unavailable.contains(url)
    }
}

/// A synchronous I/O stall with a bounded, cancellation-aware release.
/// NSCondition protects all mutable state; no callback runs while holding it.
final class BlockingBackupFileAvailability: AutomaticBackupFileAvailabilityChecking,
    @unchecked Sendable
{
    private let blockedURL: URL
    private let condition = NSCondition()
    private var arrived = false
    private var released = false

    init(blockedURL: URL) {
        self.blockedURL = blockedURL
    }

    var hasArrived: Bool {
        condition.lock()
        defer { condition.unlock() }
        return arrived
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func isDownloaded(at url: URL) throws -> Bool {
        guard url == blockedURL else { return true }
        let progress = BackupService.cancellationProgress
        progress?.cancellationHandler = { self.release() }
        defer { progress?.cancellationHandler = nil }
        condition.lock()
        defer { condition.unlock() }
        arrived = true
        let deadline = Date().addingTimeInterval(10)
        while !released {
            guard condition.wait(until: deadline) else { throw CocoaError(.fileReadUnknown) }
        }
        if progress?.isCancelled == true { throw CancellationError() }
        return true
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
