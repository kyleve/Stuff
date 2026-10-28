import Foundation

/// Reads a journal directory back — the "next launch" half of ``Journal``.
///
/// Segments are read in write order; within each, entries are validated by
/// length and CRC. An invalid or incomplete entry ends that segment's
/// recovery (the torn tail a crash leaves is expected, and it can only be
/// the final entry of the final write).
public enum JournalRecovery {
    public struct Recovered: Sendable {
        /// Every intact entry, in append order.
        public let payloads: [Data]
        /// Whether a segment ended in a torn or corrupt entry.
        public let foundTornEntry: Bool
        /// Whether the writer dropped older segments to stay in budget —
        /// entries older than `payloads.first` existed and are gone.
        public let droppedOlderEntries: Bool
    }

    /// Recover every intact entry from the journal in `directory`. A
    /// missing directory recovers as empty.
    public static func recover(directory: URL) throws -> Recovered {
        let indexes = try JournalSegments.indexes(in: directory)
        var payloads: [Data] = []
        var foundTornEntry = false
        for index in indexes {
            let data = try Data(contentsOf: JournalSegments.url(for: index, in: directory))
            let segment = JournalFraming.parse(data)
            payloads.append(contentsOf: segment.payloads)
            foundTornEntry = foundTornEntry || segment.foundTornEntry
        }
        return Recovered(
            payloads: payloads,
            foundTornEntry: foundTornEntry,
            // Segment numbering starts at 1; a higher floor means the
            // writer rotated older segments away.
            droppedOlderEntries: (indexes.first ?? 1) > 1,
        )
    }

    /// Delete the journal directory — call after ingesting a recovery.
    public static func remove(directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// Segment file naming and bookkeeping, shared by writer and recovery.
enum JournalSegments {
    private static let fileExtension = "journalsegment"

    static func url(for index: Int, in directory: URL) -> URL {
        directory.appendingPathComponent("\(index).\(fileExtension)")
    }

    /// Present segment indexes, ascending. A missing directory is empty.
    static func indexes(in directory: URL) throws -> [Int] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .compactMap { name -> Int? in
                let parts = name.split(separator: ".")
                guard parts.count == 2, parts[1] == fileExtension else { return nil }
                return Int(parts[0])
            }
            .sorted()
    }

    static func open(index: Int, in directory: URL) throws -> Int32 {
        let descriptor = Darwin.open(
            url(for: index, in: directory).path,
            O_WRONLY | O_CREAT | O_APPEND,
            0o644,
        )
        guard descriptor >= 0 else { throw JournalError.writeFailed(errno: errno) }
        return descriptor
    }

    static func byteCount(of index: Int, in directory: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url(for: index, in: directory).path,
        )
        return (attributes[.size] as? Int) ?? 0
    }
}

/// The on-disk entry framing: `[UInt32 length][UInt32 crc32][payload]`,
/// little-endian. CRC validation rejects torn and corrupt entries.
enum JournalFraming {
    /// Refuse absurd lengths (torn length bytes can decode as garbage).
    static let maximumEntryByteCount = 64 * 1024 * 1024

    static func frame(_ payload: Data) -> Data {
        var framed = Data(capacity: payload.count + 8)
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { framed.append(contentsOf: $0) }
        withUnsafeBytes(of: CRC32.checksum(payload).littleEndian) { framed.append(contentsOf: $0) }
        framed.append(payload)
        return framed
    }

    struct ParsedSegment {
        let payloads: [Data]
        let foundTornEntry: Bool
    }

    static func parse(_ data: Data) -> ParsedSegment {
        var payloads: [Data] = []
        var offset = 0
        while offset + 8 <= data.count {
            let length = Int(data.subdata(in: offset ..< offset + 4)
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            let crc = data.subdata(in: offset + 4 ..< offset + 8)
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
            let end = offset + 8 + length
            guard length <= maximumEntryByteCount, end <= data.count else {
                return ParsedSegment(payloads: payloads, foundTornEntry: true)
            }
            let payload = data.subdata(in: offset + 8 ..< end)
            guard CRC32.checksum(payload) == crc else {
                return ParsedSegment(payloads: payloads, foundTornEntry: true)
            }
            payloads.append(payload)
            offset = end
        }
        return ParsedSegment(payloads: payloads, foundTornEntry: offset != data.count)
    }
}

/// Table-driven CRC-32 (IEEE 802.3 polynomial) — entry integrity checking
/// without linking zlib.
enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0 ..< 8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
