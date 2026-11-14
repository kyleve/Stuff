import Foundation
@testable import WhereCore

actor ScriptedDataCompatibilityTransport: DataCompatibilityTransport {
    var account = DataCompatibilityAccountID(rawValue: "account-a")
    var remote: SharedDataModelVersion?
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

    func accountID() async throws -> DataCompatibilityAccountID {
        account
    }

    nonisolated func accountChanges() -> AsyncStream<Void> {
        stream
    }

    func read(accountID _: DataCompatibilityAccountID) async throws -> SharedDataModelVersion? {
        readCount += 1
        let captured = remote
        if holdsRead { await withCheckedContinuation { heldRead = $0 } }
        if let readError { throw readError }
        return captured
    }

    func advance(
        accountID _: DataCompatibilityAccountID,
        from previous: SharedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> SharedDataModelVersion {
        saveCount += 1
        if let conflictVersion {
            self.conflictVersion = nil
            remote = .init(version: conflictVersion, revision: "conflict")
            throw DataCompatibilityTransportError.conflict
        }
        guard previous == remote else { throw DataCompatibilityTransportError.conflict }
        remote = .init(version: version, revision: "save-\(saveCount)")
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

    func setVersion(_ version: Int) {
        remote = .init(
            version: .init(rawValue: version),
            revision: "changed",
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

    func changeAccount() {
        account = .init(rawValue: "account-b")
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
