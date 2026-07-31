import Foundation
import RegionKit
import Testing
import WhereCore

struct WidgetSnapshotStoreTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "WidgetSnapshotStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeSnapshot(
        dayRegions: Set<Region> = [.california, .newYork],
        totals: [Region: Int] = [.california: 132, .newYork: 41],
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            day: Date(timeIntervalSince1970: 1_700_000_000),
            year: 2026,
            dayRegions: dayRegions,
            totals: totals,
            appearances: [:],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            surface: nil,
        )
    }

    @Test func writeThenReadRoundTrips() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let snapshot = makeSnapshot()

        try store.write(snapshot)

        #expect(store.read() == snapshot)
    }

    @Test func snapshotRoundTripsThroughCodable() throws {
        let snapshot = makeSnapshot(
            dayRegions: [.california, .canada],
            totals: [.california: 1, .newYork: 2, .canada: 3, .europeanUnion: 4, .other: 5],
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test func readReturnsNilWhenNothingWritten() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)

        #expect(store.read() == nil)
    }

    /// A file that exists but won't decode (a truncated write, a stale format)
    /// still reads as the empty state — the widget has nothing better to render
    /// and the next publish overwrites it — but unlike "nothing written yet" it's
    /// a real failure, so it logs (see `WidgetSnapshotStoreLog`).
    @Test func readReturnsNilOnAnUnreadableFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a snapshot".utf8)
            .write(to: directory.appending(path: "widget-snapshot.json"))

        #expect(WidgetSnapshotStore(directory: directory).read() == nil)
    }

    @Test func writeOverwritesPreviousSnapshot() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)

        try store.write(makeSnapshot(dayRegions: [.california], totals: [.california: 1]))
        let latest = makeSnapshot(dayRegions: [.newYork], totals: [.newYork: 9])
        try store.write(latest)

        #expect(store.read() == latest)
    }
}
