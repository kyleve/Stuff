import Foundation
import os

/// An append-only, crash-durable journal of opaque `Data` entries.
///
/// `append(_:sync:)` is synchronous and safe from any thread: once it
/// returns, the entry has reached the kernel page cache and survives the
/// *process* dying by any means (crash, kill, jetsam). `.full` sync extends
/// that to kernel panics and power loss via `F_FULLFSYNC`, at
/// millisecond cost — reserve it for entries that warrant it.
///
/// Entries are framed as `[length][crc32][payload]` and written to numbered
/// segment files in the journal's directory. When the journal exceeds its
/// byte budget, the oldest segment is dropped whole (the journal favors the
/// newest entries, like a flight recorder). ``JournalRecovery`` reads a
/// directory back tolerating the torn final entry a crash can leave.
///
/// The journal is payload-agnostic: what the bytes mean, and any ordering
/// or deduplication semantics, belong to the caller.
public final class Journal: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Total byte budget across segments; on overflow the oldest
        /// segment is dropped whole.
        public var maximumByteCount: Int

        /// Re-written as the first entry of every segment, so rotation can
        /// never drop it: identity/context entries (say, a session header)
        /// stay recoverable however far the journal rotates. Recovery
        /// returns it like any other entry — expect one copy per surviving
        /// segment.
        public var segmentHeader: Data?

        public init(maximumByteCount: Int, segmentHeader: Data? = nil) {
            self.maximumByteCount = maximumByteCount
            self.segmentHeader = segmentHeader
        }
    }

    /// How durable an individual append must be before it returns.
    public enum Sync: Sendable {
        /// Page cache — survives process death; lost in a kernel panic.
        case processDeath
        /// `F_FULLFSYNC` — survives kernel panics and power loss.
        /// Milliseconds; reserve for the direst entries.
        case full
    }

    private struct State {
        var segmentIndex: Int
        var descriptor: Int32
        var segmentByteCount: Int
        var totalByteCount: Int
        var droppedSegmentCount = 0
        var isClosed = false
        /// A short write left torn bytes at the segment's tail; recovery
        /// would stop there, so nothing more may append to it — the next
        /// append rotates to a fresh segment first.
        var segmentIsPoisoned = false
        #if DEBUG
            var pendingShortWrite = false
        #endif
    }

    /// Segments rotate at half the budget so at most two exist: dropping
    /// the older one can never discard the newest entries.
    private var segmentBudget: Int {
        configuration.maximumByteCount / 2
    }

    public let directory: URL
    private let configuration: Configuration
    private let state: OSAllocatedUnfairLock<State>

    /// Opens a journal in `directory` (created if needed), continuing after
    /// the highest existing segment so prior entries are never overwritten.
    public init(directory: URL, configuration: Configuration) throws {
        self.directory = directory
        self.configuration = configuration
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try JournalSegments.indexes(in: directory)
        let index = (existing.last ?? 0) + 1
        let descriptor = try JournalSegments.open(index: index, in: directory)
        let existingBytes = try existing.reduce(0) { total, index in
            try total + (JournalSegments.byteCount(of: index, in: directory))
        }
        state = OSAllocatedUnfairLock(initialState: State(
            segmentIndex: index,
            descriptor: descriptor,
            segmentByteCount: 0,
            totalByteCount: existingBytes,
        ))
        try state.withLock { state in
            try writeSegmentHeader(&state)
        }
    }

    deinit {
        close()
    }

    /// Append one entry. Synchronous; safe from any thread. Throws when the
    /// journal is closed or the write fails (disk full). A *partial* write
    /// (some bytes landed, then failure) poisons the segment: recovery
    /// stops at torn bytes, so the next append rotates to a fresh segment
    /// rather than stranding everything written after the tear.
    public func append(_ payload: Data, sync: Sync) throws {
        let framed = JournalFraming.frame(payload)
        try state.withLock { state in
            guard !state.isClosed else { throw JournalError.closed }
            if state.segmentIsPoisoned
                ||
                (state.segmentByteCount + framed.count > segmentBudget && state
                    .segmentByteCount > 0)
            {
                try rotate(&state)
                state.segmentIsPoisoned = false
            }

            var bytesToWrite = framed[...]
            #if DEBUG
                if state.pendingShortWrite {
                    state.pendingShortWrite = false
                    bytesToWrite = framed.prefix(framed.count / 2)
                }
            #endif
            let written = bytesToWrite.withUnsafeBytes { buffer in
                write(state.descriptor, buffer.baseAddress, buffer.count)
            }

            if written == framed.count {
                state.segmentByteCount += framed.count
                state.totalByteCount += framed.count
            } else if written > 0 {
                // Torn bytes are on disk (disk-full's shape): account for
                // them and poison the segment so later entries land
                // parseably in the next one.
                state.segmentByteCount += written
                state.totalByteCount += written
                state.segmentIsPoisoned = true
                throw JournalError.writeFailed(errno: errno)
            } else {
                // Nothing landed; the segment is still clean.
                throw JournalError.writeFailed(errno: errno)
            }
            if case .full = sync {
                _ = fcntl(state.descriptor, F_FULLFSYNC)
            }
        }
    }

    #if DEBUG
        /// Testing seam: the next append writes only half its frame and
        /// reports failure — the shape of a disk-full torn write.
        @_spi(Testing) public func injectShortWriteOnNextAppend() {
            state.withLock { $0.pendingShortWrite = true }
        }
    #endif

    /// Segments dropped so far to stay within the byte budget — each one
    /// took its entries with it.
    public var droppedSegmentCount: Int {
        state.withLock(\.droppedSegmentCount)
    }

    /// Close the journal; further appends throw. Idempotent.
    public func close() {
        state.withLock { state in
            guard !state.isClosed else { return }
            Darwin.close(state.descriptor)
            state.isClosed = true
        }
    }

    private func rotate(_ state: inout State) throws {
        Darwin.close(state.descriptor)
        let next = state.segmentIndex + 1
        state.descriptor = try JournalSegments.open(index: next, in: directory)
        state.segmentIndex = next
        state.segmentByteCount = 0
        try writeSegmentHeader(&state)
        // Drop oldest segments until the (pre-append) total fits the budget.
        var indexes = try JournalSegments.indexes(in: directory)
        while state.totalByteCount > configuration.maximumByteCount, indexes.count > 1 {
            let oldest = indexes.removeFirst()
            let bytes = try JournalSegments.byteCount(of: oldest, in: directory)
            try? FileManager.default.removeItem(at: JournalSegments.url(for: oldest, in: directory))
            state.totalByteCount -= bytes
            state.droppedSegmentCount += 1
        }
    }

    /// Write the configured header as the segment's first entry — every
    /// segment must be self-describing, since rotation drops whole
    /// segments from the oldest end.
    private func writeSegmentHeader(_ state: inout State) throws {
        guard let header = configuration.segmentHeader else { return }
        let framed = JournalFraming.frame(header)
        let written = framed.withUnsafeBytes { buffer in
            write(state.descriptor, buffer.baseAddress, buffer.count)
        }
        guard written == framed.count else {
            if written > 0 {
                state.segmentIsPoisoned = true
            }
            throw JournalError.writeFailed(errno: errno)
        }
        state.segmentByteCount += framed.count
        state.totalByteCount += framed.count
    }
}

public enum JournalError: Error, Equatable {
    case closed
    case writeFailed(errno: Int32)
}
