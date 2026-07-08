import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct LocationOutboxTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "location-outbox-\(UUID().uuidString).json")
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

    @Test func savesAndLoadsRoundTrip() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let outbox = FileLocationOutbox(fileURL: url)

        let samples = [sample("2026-03-15T12:00:00Z"), sample("2026-03-15T13:00:00Z")]
        await outbox.save(samples)
        #expect(await outbox.load() == samples)
    }

    @Test func savingEmptyClearsThePersistedBacklog() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let outbox = FileLocationOutbox(fileURL: url)

        await outbox.save([sample("2026-03-15T12:00:00Z")])
        await outbox.save([])

        #expect(await outbox.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func loadingAMissingFileReturnsEmpty() async {
        let outbox = FileLocationOutbox(fileURL: tempURL())
        #expect(await outbox.load().isEmpty)
    }

    @Test func loadingACorruptFileReturnsEmptyRatherThanThrowing() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid json".utf8).write(to: url)

        let outbox = FileLocationOutbox(fileURL: url)
        #expect(await outbox.load().isEmpty)
    }
}
