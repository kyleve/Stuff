import Foundation
@_spi(Testing) import JournalKit
import Testing

struct JournalTests {
    @Test func appendsRoundTripInOrder() throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        try journal.append(payload("first"), sync: .processDeath)
        try journal.append(payload("second"), sync: .processDeath)
        try journal.append(payload("third"), sync: .full)
        journal.close()

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(texts(recovered.payloads) == ["first", "second", "third"])
        #expect(!recovered.foundTornEntry)
        #expect(!recovered.droppedOlderEntries)
    }

    @Test func closedJournalsRefuseAppends() throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        journal.close()
        #expect(throws: JournalError.closed) {
            try journal.append(payload("late"), sync: .processDeath)
        }
    }

    @Test func overBudgetJournalsDropOldestSegmentsWhole() throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // ~100-byte entries against a 1KB budget: segments rotate at 512
        // bytes and the oldest drop as the budget overflows.
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1024),
        )
        for index in 0 ..< 40 {
            try journal.append(
                payload("entry-\(index)-" + String(repeating: "x", count: 90)),
                sync: .processDeath,
            )
        }
        journal.close()

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(journal.droppedSegmentCount > 0)
        #expect(recovered.droppedOlderEntries)
        #expect(!recovered.payloads.isEmpty)
        // The newest entry always survives — the journal drops from the
        // oldest end, like a flight recorder.
        #expect(texts(recovered.payloads).last?.hasPrefix("entry-39-") == true)
    }

    @Test func tornWritesPoisonOnlyTheirSegment() throws {
        // A short write (disk-full's shape) leaves torn bytes recovery
        // stops at. The segment poisons; the next append rotates to a
        // fresh one — so a moment of disk pressure loses one entry, not
        // everything after it.
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        try journal.append(payload("before"), sync: .processDeath)
        journal.injectShortWriteOnNextAppend()
        #expect(throws: (any Error).self) {
            try journal.append(payload("torn"), sync: .processDeath)
        }
        try journal.append(payload("after"), sync: .processDeath)
        journal.close()

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(texts(recovered.payloads) == ["before", "after"])
        #expect(recovered.foundTornEntry)
        // The poisoned segment stayed behind; "after" landed in a new one.
        let segments = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(segments.count == 2)
    }

    @Test func failedSegmentRemovalsKeepTheBudgetHonest() throws {
        // A removal that fails must not be counted as if it succeeded —
        // the old accounting double-subtracted the segment's bytes on the
        // retry, drifting the total low until the budget stopped enforcing
        // and the journal grew without bound.
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1024),
        )
        for index in 0 ..< 60 {
            if index.isMultiple(of: 5) {
                journal.injectRemovalFailureOnNextRotation()
            }
            try journal.append(
                payload("entry-\(index)-" + String(repeating: "x", count: 90)),
                sync: .processDeath,
            )
        }
        journal.close()

        // Transient removal failures retried; the disk footprint stays
        // near the budget instead of growing with the append count.
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .reduce(0) { total, name in
                let path = directory.appendingPathComponent(name).path
                let size = (
                    try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
                ) ??
                    0
                return total + (size ?? 0)
            }
        #expect(onDisk <= 2048)

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(texts(recovered.payloads).last?.hasPrefix("entry-59-") == true)
        #expect(recovered.droppedOlderEntries)
    }

    @Test func segmentHeadersSurviveRotation() throws {
        // The header re-writes at every segment's start, so however far
        // the budget rotates, the newest segment self-describes — dropping
        // old segments can never orphan the journal's identity.
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(
                maximumByteCount: 1024,
                segmentHeader: payload("header"),
            ),
        )
        for index in 0 ..< 40 {
            try journal.append(
                payload("entry-\(index)-" + String(repeating: "x", count: 90)),
                sync: .processDeath,
            )
        }
        journal.close()

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(recovered.droppedOlderEntries)
        #expect(texts(recovered.payloads).first == "header")
        #expect(texts(recovered.payloads).last?.hasPrefix("entry-39-") == true)
    }

    @Test func reopeningContinuesAfterExistingSegments() throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = Journal.Configuration(maximumByteCount: 1_000_000)
        let first = try Journal(directory: directory, configuration: configuration)
        try first.append(payload("before"), sync: .processDeath)
        first.close()

        let second = try Journal(directory: directory, configuration: configuration)
        try second.append(payload("after"), sync: .processDeath)
        second.close()

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(texts(recovered.payloads) == ["before", "after"])
    }

    @Test func concurrentAppendsAllSurvive() async throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 10_000_000),
        )
        let threads = 4
        let perThread = 250
        await withTaskGroup(of: Void.self) { group in
            for thread in 0 ..< threads {
                group.addTask {
                    for index in 0 ..< perThread {
                        try? journal.append(payload("t\(thread)-\(index)"), sync: .processDeath)
                    }
                }
            }
        }
        journal.close()

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(recovered.payloads.count == threads * perThread)
        #expect(Set(texts(recovered.payloads)).count == threads * perThread)
        // Per-writer order is preserved even though writers interleave.
        for thread in 0 ..< threads {
            let mine = texts(recovered.payloads).filter { $0.hasPrefix("t\(thread)-") }
            let expected = (0 ..< perThread).map { "t\(thread)-\($0)" }
            #expect(mine == expected)
        }
    }
}
