import CloudKit
import Foundation

/// Maps the control protocol to CloudKit change tags and an atomic conditional save.
actor CloudKitDataCompatibilityControlDatabase: DataCompatibilityControlDatabase {
    private struct Payload: Codable {
        let accountID: DataCompatibilityAccountID
        let requiredMajor: UInt
    }

    private static let zoneID = CKRecordZone.ID(zoneName: "WhereDataCompatibility")
    private let container: CKContainer
    private let database: CKDatabase

    init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
    }

    func accountID() async throws -> DataCompatibilityAccountID {
        let name = try await container.userRecordID().recordName
        guard !name.isEmpty else { throw DataCompatibilityError.verificationRequired }
        return .init(rawValue: name)
    }

    func head(accountID: DataCompatibilityAccountID) async throws -> SharedDataCompatibilityState? {
        guard let record = try await fetch(accountID: accountID) else { return nil }
        return try Self.state(record, accountID: accountID)
    }

    func hasLegacyZone() async throws -> Bool {
        try await database.allRecordZones().contains {
            $0.zoneID != Self.zoneID && $0.zoneID != CKRecordZone.default().zoneID
        }
    }

    func prepareControlZone() async throws {
        _ = try await database.save(CKRecordZone(zoneID: Self.zoneID))
        let subscription = CKRecordZoneSubscription(
            zoneID: Self.zoneID,
            subscriptionID: "where-data-compatibility",
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try await database.save(subscription)
    }

    func saveHead(
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        expectedRevision: SharedDataCompatibilityState.Revision?,
    ) async throws -> SharedDataCompatibilityState {
        let record: CKRecord
        if let expectedRevision {
            guard let existing = try await fetch(accountID: accountID),
                  existing.recordChangeTag == expectedRevision.rawValue,
                  try Self.state(existing, accountID: accountID).requiredMajor <= requiredMajor
            else { throw DataCompatibilityError.concurrentChange }
            record = existing
        } else {
            record = CKRecord(
                recordType: "WhereDataCompatibility",
                recordID: Self.recordID(accountID),
            )
        }
        record["payload"] = try JSONEncoder().encode(Payload(
            accountID: accountID,
            requiredMajor: requiredMajor,
        ))
        let results = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true,
        )
        guard let result = results.saveResults[record.recordID]
        else { throw DataCompatibilityError.incompleteRecord }
        return try Self.state(result.get(), accountID: accountID)
    }

    private func fetch(accountID: DataCompatibilityAccountID) async throws -> CKRecord? {
        do { return try await database.record(for: Self.recordID(accountID)) }
        catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound { return nil }
    }

    private static func recordID(_ accountID: DataCompatibilityAccountID) -> CKRecord.ID {
        // If an account changes during a request, an old account's record name cannot replace
        // the new account's head. The transport also checks identity after every response.
        CKRecord.ID(recordName: "required-major-" + accountID.rawValue, zoneID: zoneID)
    }

    private static func state(
        _ record: CKRecord,
        accountID: DataCompatibilityAccountID,
    ) throws -> SharedDataCompatibilityState {
        guard let data = record["payload"] as? Data, let revision = record.recordChangeTag
        else { throw DataCompatibilityError.incompleteRecord }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.accountID == accountID else { throw DataCompatibilityError.accountChanged }
        return .init(
            accountID: accountID,
            requiredMajor: payload.requiredMajor,
            revision: .init(rawValue: revision),
        )
    }
}
