import CloudKit
import Foundation

/// Serializes authority changes through one mutable head and immutable events in a private zone.
///
/// Both records carry the proposal. An atomic conditional save advances the head and creates its
/// commit together. Event IDs resolve uncertain responses without replaying an already committed
/// transition. These records are separate from every CloudKit record managed by SwiftData.
/// CloudKit decides who owns recording; `SDRecordingAuthorityCommit` stores what this device
/// learned.
public actor CloudKitRecordingAuthorityTransport: RecordingAuthorityTransport {
    private let database: CKDatabase

    public init(containerIdentifier: String) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
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
        let result = try await database.modifyRecords(
            saving: [head.record, event.record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true,
        )
        guard let savedHead = result.saveResults[head.id.recordID],
              let savedEvent = result.saveResults[immutableID.recordID]
        else {
            throw RecordingAuthorityError.invalidRecord
        }
        _ = try savedHead.get()
        return try CloudKitRecordingAuthorityRecord(record: savedEvent.get(), id: immutableID)
            .commit
    }

    public func fetchCommit(for transitionID: RecordingAuthority
        .EventID) async throws -> RecordingAuthorityCommit?
    {
        try await fetch(.event(transitionID))?.commit
    }

    /// Install once at launch; pushes only prompt a refresh of authoritative state.
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

    private func fetch(_ recordID: CloudKitRecordingAuthorityRecord
        .ID) async throws -> CloudKitRecordingAuthorityRecord?
    {
        do {
            let record = try await database.record(for: recordID.recordID)
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
