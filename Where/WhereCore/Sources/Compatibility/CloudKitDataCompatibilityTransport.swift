import CloudKit
import Foundation

/// A single conditional record in a private zone, separate from SwiftData's mirror.
public actor CloudKitDataCompatibilityTransport: DataCompatibilityTransport {
    public static let subscriptionID = "where-store-compatibility"
    private enum Schema {
        static let name = "WhereStoreCompatibility"
        static let zoneID = CKRecordZone.ID(zoneName: name)
        static let recordNamePrefix = "version-"
        static let requiredVersion = "requiredVersion"
        static let accountID = "accountID"
        static let changeReason = "changeReason"
    }

    private let container: CKContainer
    private let containerIdentifier: String
    private let database: CKDatabase
    private let local: LocalDataCompatibilityTransport
    private var subscribedAccount: DataCompatibilityAccountID?
    private var retryAfter: Date?
    private static let logger = WhereLog.root(DataCompatibilityLog.self)

    public init(containerIdentifier: String, version: DataModelVersion) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.containerIdentifier = containerIdentifier
        database = container.privateCloudDatabase
        local = LocalDataCompatibilityTransport(version: version)
    }

    public func domain() async throws -> DataCompatibilityDomain {
        try await perform { transport in try await transport.resolveDomain() }
    }

    private func resolveDomain() async throws -> DataCompatibilityDomain {
        try await Self.resolveDomain(
            status: container.accountStatus(),
            containerIdentifier: containerIdentifier,
            userRecordName: { try await self.container.userRecordID().recordName },
        )
    }

    /// Only a confirmed absent account permits local operation. Authentication errors alone do not.
    static func resolveDomain(
        status: CKAccountStatus,
        containerIdentifier: String,
        userRecordName: @Sendable () async throws -> String,
    ) async throws -> DataCompatibilityDomain {
        switch status {
            case .available:
                try await .cloud(.init(
                    containerIdentifier: containerIdentifier,
                    userRecordName: userRecordName(),
                ))
            case .noAccount: .local
            case .restricted: throw CKError(.managedAccountRestricted)
            case .couldNotDetermine: throw CKError(.notAuthenticated)
            case .temporarilyUnavailable: throw CKError(.accountTemporarilyUnavailable)
            @unknown default: throw CKError(.notAuthenticated)
        }
    }

    public func read(domain: DataCompatibilityDomain) async throws -> PersistedDataModelVersion? {
        try await withDomain(domain) { transport in
            switch domain {
                case .local: return try await transport.local.read(domain: domain)
                case let .cloud(account):
                    try await transport.subscribe(account)
                    return try await transport.fetch(account).map {
                        try Self.decode($0, accountID: account)
                    }
            }
        }
    }

    public func advance(
        domain: DataCompatibilityDomain,
        from previous: PersistedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> PersistedDataModelVersion {
        try await withDomain(domain) { transport in
            switch domain {
                case .local:
                    return try await transport.local.advance(
                        domain: domain,
                        from: previous,
                        to: version,
                    )
                case let .cloud(account):
                    let record: CKRecord
                    if let previous {
                        guard let fetched = try await transport.fetch(account),
                              fetched.recordChangeTag == previous.revision,
                              try Self.decode(fetched, accountID: account).version <= version
                        else { throw DataCompatibilityTransportError.conflict }
                        record = fetched
                    } else {
                        record = CKRecord(
                            recordType: Schema.name,
                            recordID: Self.recordID(account),
                        )
                    }
                    try Task.checkCancellation()
                    try await transport.requireDomain(domain)
                    record[Schema.requiredVersion] = version.rawValue
                    record[Schema.accountID] = account.userRecordName
                    // No supported build can be locked out by baseline data. Baseline
                    // publication must also work before the optional field is deployed.
                    if version > .baseline, let reason = version.changeReason {
                        record[Schema.changeReason] = try JSONEncoder().encode(reason)
                    } else if record[Schema.changeReason] != nil {
                        record[Schema.changeReason] = nil
                    }
                    let result = try await transport.database.modifyRecords(
                        saving: [record],
                        deleting: [],
                        savePolicy: .ifServerRecordUnchanged,
                        atomically: true,
                    )
                    guard let saved = result.saveResults[record.recordID] else {
                        throw DataCompatibilityTransportError.invalidRecord
                    }
                    return try Self.decode(saved.get(), accountID: account)
            }
        }
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

    private func perform<T: Sendable>(
        _ operation: @Sendable (isolated CloudKitDataCompatibilityTransport) async throws -> T,
    ) async throws -> T {
        do {
            try checkBackoff()
            return try await operation(self)
        } catch { throw classify(error) }
    }

    private func withDomain<T: Sendable>(
        _ domain: DataCompatibilityDomain,
        operation: @Sendable (isolated CloudKitDataCompatibilityTransport) async throws -> T,
    ) async throws -> T {
        try await perform { transport in
            try await transport.requireDomain(domain)
            let result = try await operation(transport)
            try await transport.requireDomain(domain)
            return result
        }
    }

    private func requireDomain(_ expected: DataCompatibilityDomain) async throws {
        guard try await resolveDomain() == expected else {
            subscribedAccount = nil
            throw DataCompatibilityTransportError.accountChanged
        }
    }

    private func subscribe(_ account: DataCompatibilityAccountID) async throws {
        guard subscribedAccount != account else { return }
        _ = try await database.save(CKRecordZone(zoneID: Schema.zoneID))
        let subscription = CKRecordZoneSubscription(
            zoneID: Schema.zoneID,
            subscriptionID: Self.subscriptionID,
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try await database.save(subscription)
        try await requireDomain(.cloud(account))
        subscribedAccount = account
    }

    private func fetch(_ accountID: DataCompatibilityAccountID) async throws -> CKRecord? {
        do { return try await database.record(for: Self.recordID(accountID)) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    private static func recordID(_ accountID: DataCompatibilityAccountID) -> CKRecord.ID {
        // Account-specific names fence a request that crosses a switch before its conditional save.
        CKRecord.ID(
            recordName: Schema.recordNamePrefix + accountID.userRecordName,
            zoneID: Schema.zoneID,
        )
    }

    static func decode(
        _ record: CKRecord,
        accountID: DataCompatibilityAccountID,
    ) throws -> PersistedDataModelVersion {
        guard record[Schema.accountID] as? String == accountID.userRecordName,
              let value = record[Schema.requiredVersion] as? Int, value > 0,
              let revision = record.recordChangeTag
        else { throw DataCompatibilityTransportError.invalidRecord }
        return PersistedDataModelVersion(
            version: .init(rawValue: value),
            revision: revision,
            changeReason: decodeChangeReason(from: record),
        )
    }

    private static func decodeChangeReason(from record: CKRecord) -> DataModelChangeReason? {
        guard let data = record[Schema.changeReason] as? Data else { return nil }
        do { return try JSONDecoder().decode(DataModelChangeReason.self, from: data) }
        catch {
            logger.invalidChangeReason(error: .restricted(.errorDetails, error))
            return nil
        }
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
                {
                    return DataCompatibilityTransportError.conflict
                }
                return error
            case .internalError, .badContainer, .badDatabase, .serverRejectedRequest,
                 .participantAlreadyInvited, .missingEntitlement, .notAuthenticated,
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
