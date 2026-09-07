import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct SpendHistoryStoreTests {
    private func makeStore() -> (store: SpendHistoryStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpendHistoryStoreTests-\(UUID().uuidString)")
        return (SpendHistoryStore(directory: directory), directory)
    }

    private func sample(_ offset: TimeInterval, _ cents: Int) -> SpendSample {
        SpendSample(
            timestamp: Date(timeIntervalSince1970: offset),
            cycleStart: nil,
            onDemandCents: cents,
        )
    }

    @Test func missingFileLoadsEmpty() throws {
        let (store, _) = makeStore()
        #expect(try store.load().isEmpty)
    }

    @Test func roundTripsSamples() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let samples = [sample(1000, 100), sample(2000, 200)]
        try store.save(samples)
        #expect(try store.load() == samples)
    }

    @Test func prunesSamplesOlderThanRetention() {
        let (store, _) = makeStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = SpendSample(
            timestamp: now.addingTimeInterval(-60),
            cycleStart: nil,
            onDemandCents: 200,
        )
        let stale = SpendSample(
            timestamp: now.addingTimeInterval(-SpendHistoryStore.retention - 60),
            cycleStart: nil,
            onDemandCents: 100,
        )
        #expect(store.pruned([stale, fresh], now: now) == [fresh])
    }
}
