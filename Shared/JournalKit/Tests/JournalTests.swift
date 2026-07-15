import Foundation
import JournalKit
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
