import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct LocationOutboxTests {
    private enum StubReadError: Error {
        case temporarilyUnavailable
    }

    private enum StubExclusionError: Error {
        case refused
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(
                path: "LocationOutboxTests.\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
            .appending(path: "outbox.json")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func pendingURL(for url: URL) -> URL {
        url.appendingPathExtension("pending")
    }

    private func write(_ samples: [LocationSample], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode(samples).write(to: url, options: .atomic)
    }

    private func entries(_ samples: [LocationSample]) -> [LocationOutboxEntry] {
        samples.map { LocationOutboxEntry(sample: $0, dataEpochID: .initial) }
    }

    private func loadedSamples(from outbox: FileLocationOutbox) async throws -> [LocationSample] {
        try await outbox.load().map(\.sample)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var secured = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try secured.setResourceValues(values)
    }

    private func sample(_ isoString: String) -> LocationSample {
        LocationSample(
            timestamp: ISO8601DateFormatter()
                .date(from: isoString) ?? Date(timeIntervalSince1970: 0),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }

    @Test func savesAndLoadsRoundTrip() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let outbox = FileLocationOutbox(fileURL: url)

        let samples = [sample("2026-03-15T12:00:00Z"), sample("2026-03-15T13:00:00Z")]
        try await outbox.save(entries(samples))
        #expect(try await loadedSamples(from: outbox) == samples)
    }

    @Test func roundTripPreservesNoninitialDataEpoch() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let outbox = FileLocationOutbox(fileURL: url)
        let entry = try LocationOutboxEntry(
            sample: sample("2026-03-15T12:00:00Z"),
            dataEpochID: WhereDataEpochID(rawValue: #require(UUID(
                uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            ))),
        )

        try await outbox.save([entry])

        #expect(try await outbox.load() == [entry])
    }

    @Test func persistedBacklogIsExcludedFromDeviceBackup() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let outbox = FileLocationOutbox(fileURL: url)

        try await outbox.save(entries([sample("2026-03-15T12:00:00Z")]))

        let values = try url.deletingLastPathComponent()
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func constructingTheOutboxSecuresAFileLeftByAnOlderBuild() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode([sample("2026-03-15T12:00:00Z")]).write(to: url)

        _ = FileLocationOutbox(fileURL: url)

        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func constructionPromotesACompletePendingFirstWrite() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pendingURL = pendingURL(for: url)
        let samples = [sample("2026-03-15T12:00:00Z")]
        try write(samples, to: pendingURL)

        let outbox = FileLocationOutbox(fileURL: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: pendingURL.path) == false)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(try await loadedSamples(from: outbox) == samples)
    }

    @Test func constructionPromotesPendingOverThePreviousBacklog() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pendingURL = pendingURL(for: url)
        let previous = [sample("2026-03-15T12:00:00Z")]
        let pending = [
            sample("2026-03-15T12:00:00Z"),
            sample("2026-03-15T13:00:00Z"),
        ]
        try write(previous, to: url)
        try write(pending, to: pendingURL)

        let outbox = FileLocationOutbox(fileURL: url)

        #expect(try await loadedSamples(from: outbox) == pending)
        #expect(FileManager.default.fileExists(atPath: pendingURL.path) == false)
    }

    @Test func corruptPendingBacklogIsDroppedWithoutReplacingThePreviousCopy() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pendingURL = pendingURL(for: url)
        let previous = [sample("2026-03-15T12:00:00Z")]
        try write(previous, to: url)
        try Data("not valid json".utf8).write(to: pendingURL, options: .atomic)

        let outbox = FileLocationOutbox(fileURL: url)

        #expect(try await loadedSamples(from: outbox) == previous)
        #expect(FileManager.default.fileExists(atPath: pendingURL.path) == false)
    }

    @Test func pendingExclusionFailureDiscardsOnlyTheInsecureCopy() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pendingURL = pendingURL(for: url)
        let previous = [sample("2026-03-15T12:00:00Z")]
        try write(previous, to: url)
        try write([sample("2026-03-15T13:00:00Z")], to: pendingURL)

        let outbox = FileLocationOutbox(
            fileURL: url,
            readData: { try Data(contentsOf: $0) },
            excludeFromBackup: { candidate in
                guard candidate != pendingURL else { throw StubExclusionError.refused }
                try Self.excludeFromBackup(candidate)
            },
        )

        #expect(try await loadedSamples(from: outbox) == previous)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: url
                .deletingLastPathComponent().path)
            .contains { $0.hasSuffix(".journalsegment") })
        #expect(FileManager.default.fileExists(atPath: pendingURL.path) == false)
    }

    @Test func finalExclusionFailureDiscardsThePromotedCopy() throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pendingURL = pendingURL(for: url)
        try write([sample("2026-03-15T12:00:00Z")], to: pendingURL)

        _ = FileLocationOutbox(
            fileURL: url,
            readData: { try Data(contentsOf: $0) },
            excludeFromBackup: { candidate in
                guard candidate != url else { throw StubExclusionError.refused }
                try Self.excludeFromBackup(candidate)
            },
        )

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        #expect(FileManager.default.fileExists(atPath: pendingURL.path) == false)
    }

    @Test func savingEmptyClearsThePersistedBacklog() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let outbox = FileLocationOutbox(fileURL: url)

        try await outbox.save(entries([sample("2026-03-15T12:00:00Z")]))
        try await outbox.save([])

        #expect(try await outbox.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test func clearAlsoRemovesALegacyBacklogLeftByFailedMigration() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let legacyURL = url.deletingLastPathComponent().appending(path: "legacy.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode([sample("2026-03-15T12:00:00Z")]).write(to: legacyURL)
        let outbox = FileLocationOutbox(fileURL: url, legacyFileURL: legacyURL)

        try await outbox.clear()

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func loadingAMissingFileReturnsEmpty() async throws {
        let outbox = FileLocationOutbox(fileURL: tempURL())
        #expect(try await outbox.load().isEmpty)
    }

    @Test func loadingACorruptFileThrowsAfterDiscardingIt() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not valid json".utf8).write(to: url)

        let outbox = FileLocationOutbox(fileURL: url)
        await #expect(throws: DecodingError.self) {
            try await outbox.load()
        }
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func transientReadFailurePreservesBacklogForALaterRetry() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let samples = [sample("2026-03-15T12:00:00Z")]
        try write(samples, to: url)
        let unavailableMarkerURL = url.appendingPathExtension("unavailable")
        try Data().write(to: unavailableMarkerURL)
        let outbox = FileLocationOutbox(fileURL: url) { fileURL in
            guard FileManager.default.fileExists(atPath: unavailableMarkerURL.path) == false else {
                throw StubReadError.temporarilyUnavailable
            }
            return try Data(contentsOf: fileURL)
        }

        await #expect(throws: StubReadError.self) {
            try await outbox.load()
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.removeItem(at: unavailableMarkerURL)
        #expect(try await loadedSamples(from: outbox) == samples)
    }

    @Test func newestCompleteJournalSnapshotWinsAfterRelaunch() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let first = [sample("2026-03-15T12:00:00Z")]
        let second = first + [sample("2026-03-15T13:00:00Z")]
        let writer = FileLocationOutbox(fileURL: url)
        try await writer.save(entries(first))
        try await writer.save(entries(second))
        await writer.closeJournalForTesting()

        let recovered = FileLocationOutbox(fileURL: url)

        #expect(try await loadedSamples(from: recovered) == second)
    }

    @Test func tornFinalJournalSnapshotFallsBackToPreviousCompleteSnapshot() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let first = [sample("2026-03-15T12:00:00Z")]
        let second = first + [sample("2026-03-15T13:00:00Z")]
        let writer = FileLocationOutbox(fileURL: url)
        try await writer.save(entries(first))
        try await writer.save(entries(second))
        await writer.closeJournalForTesting()
        let segmentURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: nil,
            ).first { $0.pathExtension == "journalsegment" },
        )
        let handle = try FileHandle(forWritingTo: segmentURL)
        let byteCount = try handle.seekToEnd()
        try handle.truncate(atOffset: byteCount - 4)
        try handle.close()

        let recovered = FileLocationOutbox(fileURL: url)

        #expect(try await loadedSamples(from: recovered) == first)
    }

    @Test func legacyJSONMigratesToJournalBeforeItIsRemoved() async throws {
        let url = tempURL()
        defer { cleanup(url) }
        let samples = [sample("2026-03-15T12:00:00Z")]
        try write(samples, to: url)
        let outbox = FileLocationOutbox(fileURL: url)

        #expect(try await loadedSamples(from: outbox) == samples)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: url
                .deletingLastPathComponent().path)
            .contains { $0.hasSuffix(".journalsegment") })
    }
}
