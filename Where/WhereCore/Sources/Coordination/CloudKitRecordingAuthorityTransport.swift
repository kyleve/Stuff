import CloudKit
import Foundation

/// A dedicated private-zone register. Never reads or modifies SwiftData's CloudKit records.
public actor CloudKitRecordingAuthorityTransport: RecordingAuthorityTransport {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(
        zoneName: "WhereRecordingAuthority",
        ownerName: CKCurrentUserDefaultName,
    )

    public init(containerIdentifier: String) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    public func current() async throws -> RecordingAuthorityCommit? {
        guard let head = try await fetch(headID) else { return nil }
        let proposal = try Self.decode(head)
        guard let revision = proposal.result.revision,
              let event = try await fetch(eventID(revision.eventID))
        else {
            throw RecordingAuthorityError.invalidRecord
        }
        let receipt = try receipt(event)
        guard receipt.proposal == proposal else { throw RecordingAuthorityError.invalidRecord }
        return receipt
    }

    public func commit(_ proposal: RecordingAuthorityProposal) async throws
        -> RecordingAuthorityCommit
    {
        try proposal.validate()
        guard let transitionID = proposal.result.revision?.eventID
        else { throw RecordingAuthorityError.invalidRecord }
        // Creating the same custom zone is idempotent; no SwiftData zone is touched.
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let immutableID = eventID(transitionID)
        if let existing = try await fetch(immutableID) {
            let committed = try receipt(existing)
            guard committed.proposal == proposal else { throw RecordingAuthorityError.conflict }
            return committed
        }
        let existingHead = try await fetch(headID)
        let currentState = try existingHead.map { try Self.decode($0).result } ?? .initial
        guard currentState == proposal.expected else { throw RecordingAuthorityError.conflict }
        let head = existingHead ?? CKRecord(recordType: "WhereAuthorityHead", recordID: headID)
        let event = CKRecord(recordType: "WhereAuthorityEvent", recordID: immutableID)
        let payload = try JSONEncoder().encode(proposal)
        head["payload"] = payload as CKRecordValue
        event["payload"] = payload as CKRecordValue
        // Both records must succeed. A losing change tag cannot leave an orphan receipt.
        let result: SaveResults
        do {
            let saved = try await database.modifyRecords(
                saving: [head, event],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true,
            )
            result = SaveResults(records: saved.saveResults)
        } catch {
            if Self.isConflict(error) { throw RecordingAuthorityError.conflict }
            throw error
        }
        guard let savedHead = result.records[headID],
              let savedEvent = result.records[immutableID]
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
            return try receipt(savedEvent.get())
        } catch {
            if Self.isConflict(error) { throw RecordingAuthorityError.conflict }
            throw error
        }
    }

    public func receipt(for transitionID: RecordingAuthority
        .EventID) async throws -> RecordingAuthorityCommit?
    {
        try await fetch(eventID(transitionID)).map { try receipt($0) }
    }

    /// Install once at launch; pushes only prompt a refresh of authoritative state.
    public func subscribe() async throws {
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
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

    private var headID: CKRecord.ID {
        .init(recordName: "head", zoneID: zoneID)
    }

    private func eventID(_ transitionID: RecordingAuthority.EventID) -> CKRecord.ID {
        .init(recordName: transitionID.rawValue.uuidString.lowercased(), zoneID: zoneID)
    }

    private func fetch(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound
        {
            // Only a genuinely absent record means no authority. Authentication/network failures
            // throw.
            return nil
        }
    }

    static func decode(_ record: CKRecord) throws -> RecordingAuthorityProposal {
        guard let payload = record["payload"] as? Data
        else { throw RecordingAuthorityError.invalidRecord }
        let proposal = try JSONDecoder().decode(RecordingAuthorityProposal.self, from: payload)
        try proposal.validate()
        return proposal
    }

    private func receipt(_ record: CKRecord) throws -> RecordingAuthorityCommit {
        guard let committedAt = record.creationDate
        else { throw RecordingAuthorityError.invalidRecord }
        let proposal = try Self.decode(record)
        guard let revision = proposal.result.revision,
              record.recordID == eventID(revision.eventID)
        else {
            throw RecordingAuthorityError.invalidRecord
        }
        return .init(proposal: proposal, committedAt: committedAt)
    }
}
