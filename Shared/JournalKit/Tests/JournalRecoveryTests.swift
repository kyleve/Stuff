import Foundation
@testable import JournalKit
import Testing

struct JournalRecoveryTests {
    @Test func missingDirectoriesRecoverEmpty() throws {
        let recovered = try JournalRecovery.recover(directory: makeJournalDirectory())
        #expect(recovered.payloads.isEmpty)
        #expect(!recovered.foundTornEntry)
        #expect(!recovered.droppedOlderEntries)
    }

    @Test func truncationAtEveryByteRecoversEveryWholeEntry() throws {
        // The fuzz that pins torn-tail behavior: a crash can cut the file
        // at any byte; recovery must yield exactly the entries wholly
        // written before the cut, flag the tear, and never throw.
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        let entries = ["alpha", "beta-longer", "gamma-longest-of-all"]
        for entry in entries {
            try journal.append(payload(entry), sync: .processDeath)
        }
        journal.close()

        let segment = JournalSegments.url(for: 1, in: directory)
        let full = try Data(contentsOf: segment)
        let wholeLengths = entries.map { 8 + $0.utf8.count }
        for cut in 0 ... full.count {
            try full.prefix(cut).write(to: segment)
            let recovered = try JournalRecovery.recover(directory: directory)

            var survivors = 0
            var consumed = 0
            for length in wholeLengths {
                guard consumed + length <= cut else { break }
                consumed += length
                survivors += 1
            }
            #expect(texts(recovered.payloads) == Array(entries.prefix(survivors)))
            #expect(recovered.foundTornEntry == (cut != consumed))
        }
    }

    @Test func corruptEntriesEndRecoveryAtTheLastGoodOne() throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        try journal.append(payload("good"), sync: .processDeath)
        try journal.append(payload("corrupted"), sync: .processDeath)
        journal.close()

        // Flip one payload byte of the second entry; its CRC must reject it.
        let segment = JournalSegments.url(for: 1, in: directory)
        var bytes = try Data(contentsOf: segment)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: segment)

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(texts(recovered.payloads) == ["good"])
        #expect(recovered.foundTornEntry)
    }

    @Test func absurdLengthPrefixesAreRejectedNotAllocated() throws {
        let directory = makeJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A "length" of UInt32.max from torn bytes must not be trusted.
        var bogus = Data()
        withUnsafeBytes(of: UInt32.max.littleEndian) { bogus.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32.zero.littleEndian) { bogus.append(contentsOf: $0) }
        bogus.append(Data(repeating: 0xAB, count: 32))
        try bogus.write(to: JournalSegments.url(for: 1, in: directory))

        let recovered = try JournalRecovery.recover(directory: directory)
        #expect(recovered.payloads.isEmpty)
        #expect(recovered.foundTornEntry)
    }

    @Test func removeDeletesTheDirectoryAndToleratesAbsence() throws {
        let directory = makeJournalDirectory()
        let journal = try Journal(
            directory: directory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        try journal.append(payload("entry"), sync: .processDeath)
        journal.close()

        try JournalRecovery.remove(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try JournalRecovery.remove(directory: directory) // no throw on absence
    }
}
