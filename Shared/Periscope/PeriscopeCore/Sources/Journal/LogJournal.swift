import Foundation
import JournalKit
import os

/// The live crash journal: encodes log-layer envelopes and appends them
/// through JournalKit synchronously on the emitting thread, so every
/// record survives the process dying before the async pipeline drains.
///
/// Owned by `PeriscopeStore` (which knows the session and where journals
/// live) and installed into `Periscope` when the store is added as a sink.
/// Append failures never propagate into the pipeline — they count and log
/// to OSLog, and the async path keeps delivering.
@_spi(Testing) public final class LogJournal: Sendable {
    /// Total on-disk budget per session journal; beyond it the oldest
    /// segment drops whole (flight-recorder posture).
    static let byteBudget = 8 * 1024 * 1024

    /// Records at this level or above `F_FULLFSYNC` before returning —
    /// kernel-panic durability for the direst records, milliseconds each,
    /// rare by definition.
    static let fullSyncFloor = LogLevel.fault

    private static let failureLogger = os.Logger(
        subsystem: "com.stuff.periscope",
        category: "LogJournal",
    )

    @_spi(Testing) public let directory: URL
    private let journal: Journal
    private let failureCount = OSAllocatedUnfairLock(initialState: 0)

    /// Opens the journal and writes the session entry, so a recovered
    /// journal attributes itself without external context.
    @_spi(Testing) public init(directory: URL, session: LogSession) throws {
        self.directory = directory
        journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: Self.byteBudget),
        )
        try journal.append(LogJournalEntry.session(session).encoded(), sync: .processDeath)
    }

    /// Journal one emitted record. `sequence` (stamped under the pipeline's
    /// state lock) orders replay, so appends may race here without
    /// reordering recovery.
    @_spi(Testing) public func append(_ record: LogRecord, sequence: Int) {
        do {
            let entry = try LogJournalEntry.record(LogJournalRecord(
                record: record,
                sequence: sequence,
            ))
            try journal.append(
                entry.encoded(),
                sync: record.level >= Self.fullSyncFloor ? .full : .processDeath,
            )
        } catch {
            noteFailure(error)
        }
    }

    /// Journal a scope definition — recovered records need the hierarchy.
    func append(scope: LogScope) {
        do {
            try journal.append(LogJournalEntry.scope(scope).encoded(), sync: .processDeath)
        } catch {
            noteFailure(error)
        }
    }

    /// Close the underlying journal (tests; production journals live for
    /// the process).
    @_spi(Testing) public func close() {
        journal.close()
    }

    /// Appends that failed (encoding or I/O) — observable telemetry, since
    /// journal failures must not throw into the emit path.
    @_spi(Testing) public var appendFailureCount: Int {
        failureCount.withLock { $0 }
    }

    private func noteFailure(_ error: any Error) {
        let count = failureCount.withLock { count -> Int in
            count += 1
            return count
        }
        // Log the first failure and then every 100th — an unwritable disk
        // would otherwise spam OSLog once per record.
        if count == 1 || count.isMultiple(of: 100) {
            Self.failureLogger.warning("Journal append failed (\(count)): \(error)")
        }
    }
}
