import CloudKit
import Foundation

/// Serializes authority changes through one mutable head and immutable events in a private zone.
///
/// Both records carry the proposal. An atomic conditional save advances the head and creates its
/// commit together. Event IDs resolve uncertain responses without replaying an already committed
/// transition. These records are separate from every CloudKit record managed by SwiftData.
/// CloudKit decides who owns recording; `SDRecordingAuthorityCommit` stores what this device
/// learned.
/// The private database requires an iCloud account. Authentication failures throw; they never
/// imply an empty authority or select the local development transport.
public actor CloudKitRecordingAuthorityTransport: RecordingAuthorityTransport {
    private let container: CKContainer
    private let database: CKDatabase

    public init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
    }

    public func accountID() async throws -> RecordingAccountID {
        try await .cloudKit(recordName: container.userRecordID().recordName)
    }

    public func current() async throws -> RecordingAuthorityCommit? {
        guard let head = try await fetch(.head) else { return nil }
        // The head is a pointer to a committed transition, not a commit on its own. Match its
        // payload to the immutable event so the returned timestamp always belongs to that event.
        let proposal = try head.proposal
        guard let revision = proposal.result.revision,
              let event = try await fetch(.event(revision.eventID))
        else {
            throw RecordingAuthorityError.invalidRecord
        }
        let commit = try event.commit
        guard commit.proposal == proposal else { throw RecordingAuthorityError.invalidRecord }
        return commit
    }

    public func commit(_ proposal: RecordingAuthorityProposal) async throws
        -> RecordingAuthorityCommit
    {
        try DataAccessPermit.current?.validate()
        try proposal.validate()
        guard let transitionID = proposal.result.revision?.eventID
        else { throw RecordingAuthorityError.invalidRecord }
        // Creating the same custom zone is idempotent; no SwiftData zone is touched.
        _ = try await database.save(CKRecordZone(zoneID: CloudKitRecordingAuthorityRecord.zoneID))
        let immutableID = CloudKitRecordingAuthorityRecord.ID.event(transitionID)
        // Resolve retries first. The proposal can have committed before another device changed
        // ownership, so the current head alone cannot establish this proposal's outcome.
        if let existing = try await fetch(immutableID) {
            let committed = try existing.commit
            guard committed.proposal == proposal else { throw RecordingAuthorityError.conflict }
            return committed
        }
        let existingHead = try await fetch(.head)
        let currentState = try existingHead?.proposal.result ?? .initial
        // This comparison checks the reviewed decision. The save policy below also rejects a writer
        // that changes the head after this read, using the fetched record's CloudKit change tag.
        guard currentState == proposal.expected else { throw RecordingAuthorityError.conflict }
        let head = try existingHead ?? CloudKitRecordingAuthorityRecord(
            id: .head,
            proposal: proposal,
        )
        try head.setProposal(proposal)
        let event = try CloudKitRecordingAuthorityRecord(id: immutableID, proposal: proposal)
        // Both records must succeed. A losing change tag cannot leave an orphan commit.
        // The coordinator's later SwiftData projection is a separate transaction.
        let result: SaveResults
        do {
            try DataAccessPermit.current?.validate()
            let saved = try await database.modifyRecords(
                saving: [head.record, event.record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true,
            )
            try DataAccessPermit.current?.validate()
            result = SaveResults(records: saved.saveResults)
        } catch {
            if Self.isConflict(error) { throw RecordingAuthorityError.conflict }
            throw error
        }
        guard let savedHead = result.records[head.id.recordID],
              let savedEvent = result.records[immutableID.recordID]
        else {
            throw RecordingAuthorityError.invalidRecord
        }
        for result in [savedHead, savedEvent] {
            if case let .failure(error) = result, Self.isConflict(error) {
                throw RecordingAuthorityError.conflict
            }
        }
        do {
            _ = try savedHead.get()
            return try CloudKitRecordingAuthorityRecord(record: savedEvent.get(), id: immutableID)
                .commit
        } catch {
            if Self.isConflict(error) { throw RecordingAuthorityError.conflict }
            throw error
        }
    }

    public func fetchCommit(for transitionID: RecordingAuthority
        .EventID) async throws -> RecordingAuthorityCommit?
    {
        try await fetch(.event(transitionID))?.commit
    }

    /// Ensure the current account has the persistent subscription that prompts authority refreshes.
    ///
    /// CloudKit retains subscriptions across launches. Re-saving this stable ID at startup or
    /// after an account change repairs missing setup without creating another subscription.
    /// Do not persist a device-wide "installed" flag: the account or custom zone can change.
    public func subscribe() async throws {
        _ = try await database.save(CKRecordZone(zoneID: CloudKitRecordingAuthorityRecord.zoneID))
        let subscription = CKRecordZoneSubscription(
            zoneID: CloudKitRecordingAuthorityRecord.zoneID,
            subscriptionID: "where-recording-authority-v1",
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try await database.save(subscription)
    }

    private struct SaveResults {
        let records: [CKRecord.ID: Result<CKRecord, any Error>]
    }

    static func isTemporarilyUnavailable(_ error: any Error) -> Bool {
        guard let error = error as? CKError else { return false }
        return [
            .networkUnavailable,
            .networkFailure,
            .serviceUnavailable,
            .requestRateLimited,
            .zoneBusy,
        ].contains(error.code)
    }

    static func isConflict(_ error: any Error) -> Bool {
        guard let error = error as? CKError else { return false }
        if error.code == .serverRecordChanged { return true }
        guard error.code == .partialFailure,
              let errors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error]
        else { return false }
        return errors.values.contains(where: isConflict)
    }

    private func fetch(_ recordID: CloudKitRecordingAuthorityRecord
        .ID) async throws -> CloudKitRecordingAuthorityRecord?
    {
        do {
            try DataAccessPermit.current?.validate()
            let record = try await database.record(for: recordID.recordID)
            try DataAccessPermit.current?.validate()
            return try CloudKitRecordingAuthorityRecord(record: record, id: recordID)
        } catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound
        {
            // Only a genuinely absent record means no authority. Authentication/network failures
            // throw.
            return nil
        }
    }
}
