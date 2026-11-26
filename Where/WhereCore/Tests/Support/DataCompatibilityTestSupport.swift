import Foundation
@testable import WhereCore

actor ScriptedDataCompatibilityTransport: DataCompatibilityTransport {
    var currentDomain = DataCompatibilityDomain.cloud(.init(
        containerIdentifier: "iCloud.test",
        userRecordName: "account-a",
    ))
    var remote: PersistedDataModelVersion?
    var readError: (any Error)?
    var saveError: (any Error)?
    var saveCount = 0
    var readCount = 0
    var conflictVersion: DataModelVersion?
    private var heldRead: CheckedContinuation<Void, Never>?
    private var holdsRead = false
    private nonisolated let stream: AsyncStream<Void>
    private nonisolated let continuation: AsyncStream<Void>.Continuation

    init(version: Int?) {
        remote = version.map { .init(version: .init(rawValue: $0), revision: "initial") }
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func domain() async throws -> DataCompatibilityDomain {
        currentDomain
    }

    nonisolated func accountChanges() -> AsyncStream<Void> {
        stream
    }

    func read(domain _: DataCompatibilityDomain) async throws -> PersistedDataModelVersion? {
        readCount += 1
        let captured = remote
        if holdsRead { await withCheckedContinuation { heldRead = $0 } }
        if let readError { throw readError }
        return captured
    }

    func advance(
        domain _: DataCompatibilityDomain,
        from previous: PersistedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> PersistedDataModelVersion {
        saveCount += 1
        if let conflictVersion {
            self.conflictVersion = nil
            remote = .init(version: conflictVersion, revision: "conflict")
            throw DataCompatibilityTransportError.conflict
        }
        guard previous == remote else { throw DataCompatibilityTransportError.conflict }
        remote = .init(
            version: version,
            revision: "save-\(saveCount)",
            changeReason: version > .baseline ? version.changeReason : nil,
        )
        if let saveError { throw saveError }
        return remote!
    }

    func setReadError(_ error: (any Error)?) {
        readError = error
    }

    func setSaveError(_ error: (any Error)?) {
        saveError = error
    }

    func conflict(with version: Int) {
        conflictVersion = .init(rawValue: version)
    }

    func setVersion(_ version: Int, reason: DataModelChangeReason? = nil) {
        remote = .init(
            version: .init(rawValue: version),
            revision: "changed",
            changeReason: reason,
        )
    }

    func holdRead() {
        holdsRead = true
    }

    var isReadHeld: Bool {
        heldRead != nil
    }

    func releaseRead() {
        holdsRead = false; heldRead?.resume(); heldRead = nil
    }

    func setDomain(_ domain: DataCompatibilityDomain, notify: Bool) {
        currentDomain = domain
        if notify { continuation.yield() }
    }

    func changeAccount() {
        currentDomain = .cloud(.init(
            containerIdentifier: "iCloud.test",
            userRecordName: "account-b",
        ))
        continuation.yield()
    }
}

@MainActor
final class InMemoryDataCompatibilityReceipt: DataCompatibilityReceiptStoring {
    var receipt: DataCompatibilityReceipt?
    var failure: (any Error)?

    init(receipt: DataCompatibilityReceipt? = nil) {
        self.receipt = receipt
    }

    func load() throws -> DataCompatibilityReceipt? {
        if let failure { throw failure }
        return receipt
    }

    func save(_ receipt: DataCompatibilityReceipt) throws {
        if let failure { throw failure }
        self.receipt = receipt
    }
}

@MainActor
func waitForCompatibility(_ predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await !predicate() {
        guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
        try await Task.sleep(for: .milliseconds(1))
    }
}
