import CloudKit
import Foundation
@testable import WhereCore

/// Conditional shared control storage, independent of either installation's copied files.
/// CloudKit transport verification and compare-and-save run unchanged over this adapter.
actor InstallationSharedAccount: DataCompatibilityControlDatabase {
    private let account = DataCompatibilityAccountID(rawValue: UUID().uuidString)
    private var control: SharedDataCompatibilityState?
    private var revision = 0
    private var legacyZone = false
    var online = true
    private var responseToLose = false
    private(set) var successfulSaves = 0
    private(set) var conditionalConflicts = 0
    private var holdsInitialSaves = false
    private var initialSaves: [CheckedContinuation<Void, Never>] = []

    var pendingInitialSaveCount: Int {
        initialSaves.count
    }

    func holdInitialSaves() {
        holdsInitialSaves = true
    }

    func releaseInitialSaves() {
        holdsInitialSaves = false
        let pending = initialSaves
        initialSaves.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    func setOnline(_ value: Bool) {
        online = value
    }

    func loseNextSaveResponse() {
        responseToLose = true
    }

    func markMirrorCreated() {
        legacyZone = true
    }

    func accountID() -> DataCompatibilityAccountID {
        account
    }

    func head(accountID: DataCompatibilityAccountID) throws -> SharedDataCompatibilityState? {
        try requireOnline()
        guard accountID == account else { throw DataCompatibilityError.accountChanged }
        return control
    }

    func hasLegacyZone() throws -> Bool {
        try requireOnline(); return legacyZone
    }

    func prepareControlZone() throws {
        try requireOnline()
    }

    func saveHead(
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        expectedRevision: SharedDataCompatibilityState.Revision?,
    ) async throws -> SharedDataCompatibilityState {
        if holdsInitialSaves, expectedRevision == nil {
            await withCheckedContinuation { initialSaves.append($0) }
        }
        try Task.checkCancellation()
        try requireOnline()
        guard accountID == account else { throw DataCompatibilityError.accountChanged }
        guard control?.revision == expectedRevision,
              (control?.requiredMajor ?? 0) <= requiredMajor
        else {
            conditionalConflicts += 1
            throw DataCompatibilityError.concurrentChange
        }
        revision += 1
        let saved = SharedDataCompatibilityState(
            accountID: account,
            requiredMajor: requiredMajor,
            revision: .init(rawValue: String(revision)),
        )
        control = saved
        successfulSaves += 1
        if responseToLose { responseToLose = false; throw CKError(.networkFailure) }
        return saved
    }

    func requireMajor(_ major: UInt) async throws {
        _ = try await saveHead(
            accountID: account,
            requiredMajor: major,
            expectedRevision: control?.revision,
        )
    }

    private func requireOnline() throws {
        if !online { throw CKError(.networkUnavailable) }
    }
}
