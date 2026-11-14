import CloudKit
import Foundation

/// A single conditional record in a private zone, separate from SwiftData's mirror.
public actor CloudKitDataCompatibilityTransport: DataCompatibilityTransport {
    public static let subscriptionID = "where-store-compatibility"
    private static let zoneID = CKRecordZone.ID(zoneName: "WhereStoreCompatibility")
    private let container: CKContainer
    private let database: CKDatabase
    private var subscribedAccount: DataCompatibilityAccountID?
    private var retryAfter: Date?

    public init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
    }

    public func accountID() async throws -> DataCompatibilityAccountID {
        do {
            try checkBackoff()
            return try await DataCompatibilityAccountID(rawValue: container.userRecordID()
                .recordName)
        } catch { throw classify(error) }
    }

    public func read(accountID: DataCompatibilityAccountID) async throws
        -> SharedDataModelVersion?
    {
        do {
            try checkBackoff()
            try await requireAccount(accountID)
            if subscribedAccount != accountID {
                _ = try await database.save(CKRecordZone(zoneID: Self.zoneID))
                let subscription = CKRecordZoneSubscription(
                    zoneID: Self.zoneID,
                    subscriptionID: Self.subscriptionID,
                )
                let notification = CKSubscription.NotificationInfo()
                notification.shouldSendContentAvailable = true
                subscription.notificationInfo = notification
                _ = try await database.save(subscription)
                try await requireAccount(accountID)
                subscribedAccount = accountID
            }
            let record = try await fetch(accountID)
            try await requireAccount(accountID)
            return try record.map { try Self.decode($0, accountID: accountID) }
        } catch { throw classify(error) }
    }

    public func advance(
        accountID: DataCompatibilityAccountID,
        from previous: SharedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> SharedDataModelVersion {
        do {
            try checkBackoff()
            try await requireAccount(accountID)
            let record: CKRecord
            if let previous {
                guard let fetched = try await fetch(accountID),
                      fetched.recordChangeTag == previous.revision,
                      try Self.decode(fetched, accountID: accountID).version <= version
                else { throw DataCompatibilityTransportError.conflict }
                record = fetched
            } else {
                record = CKRecord(
                    recordType: "WhereStoreCompatibility",
                    recordID: Self.recordID(accountID),
                )
            }
            try Task.checkCancellation()
            try await requireAccount(accountID)
            record["requiredVersion"] = version.rawValue
            record["accountID"] = accountID.rawValue
            let result = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true,
            )
            guard let saved = result.saveResults[record.recordID] else {
                throw DataCompatibilityTransportError.invalidRecord
            }
            try await requireAccount(accountID)
            return try Self.decode(saved.get(), accountID: accountID)
        } catch { throw classify(error) }
    }

    public nonisolated func accountChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { break }
                continuation.yield()
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func requireAccount(_ expected: DataCompatibilityAccountID) async throws {
        guard try await accountID() == expected else {
            subscribedAccount = nil
            throw DataCompatibilityTransportError.accountChanged
        }
    }

    private func fetch(_ accountID: DataCompatibilityAccountID) async throws -> CKRecord? {
        do { return try await database.record(for: Self.recordID(accountID)) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    private static func recordID(_ accountID: DataCompatibilityAccountID) -> CKRecord.ID {
        // A request crossing an account switch cannot overwrite the other account's canonical head.
        CKRecord.ID(recordName: "version-" + accountID.rawValue, zoneID: zoneID)
    }

    static func decode(
        _ record: CKRecord,
        accountID: DataCompatibilityAccountID,
    ) throws -> SharedDataModelVersion {
        guard record["accountID"] as? String == accountID.rawValue,
              let value = record["requiredVersion"] as? Int, value > 0,
              let revision = record.recordChangeTag
        else { throw DataCompatibilityTransportError.invalidRecord }
        return SharedDataModelVersion(version: .init(rawValue: value), revision: revision)
    }

    private func checkBackoff() throws {
        if let retryAfter, Date() < retryAfter {
            throw DataCompatibilityTransportError.unavailable(CKError(.requestRateLimited))
        }
    }

    private func classify(_ error: any Error) -> any Error {
        guard let cloudError = error as? CKError else { return error }
        if let interval = cloudError.retryAfterSeconds {
            retryAfter = Date().addingTimeInterval(interval)
        }
        switch cloudError.code {
            case .serverRecordChanged: return DataCompatibilityTransportError.conflict
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
                 .zoneBusy, .serverResponseLost:
                return DataCompatibilityTransportError.unavailable(error)
            case .partialFailure:
                if let errors = cloudError.partialErrorsByItemID,
                   errors.values.contains(where: { ($0 as? CKError)?.code == .serverRecordChanged })
                { return DataCompatibilityTransportError.conflict }
                return error
            case .internalError, .badContainer, .missingEntitlement, .notAuthenticated,
                 .permissionFailure, .unknownItem, .invalidArguments, .resultsTruncated,
                 .assetFileNotFound, .assetFileModified, .incompatibleVersion, .constraintViolation,
                 .operationCancelled, .changeTokenExpired, .batchRequestFailed, .zoneNotFound,
                 .limitExceeded, .quotaExceeded, .userDeletedZone, .tooManyParticipants,
                 .alreadyShared, .referenceViolation, .managedAccountRestricted,
                 .participantMayNeedVerification,
                 .assetNotAvailable, .accountTemporarilyUnavailable:
                return error
            @unknown default: return error
        }
    }
}
