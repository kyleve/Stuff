import Foundation
import Testing
@testable import WhereCore

/// `SwiftDataStore` behavior as a `WhereStore` — specifically the `changes()`
/// signal that backs the app's single read-refresh path. The fan-out itself is
/// covered by `StoreChangeBroadcasterTests`; here we assert the *store* fires it
/// on a committed `perform` and stays silent on a rolled-back one.
struct SwiftDataStoreTests {
    private let day = DayPresence(
        date: Date(timeIntervalSince1970: 0),
        regions: [.california],
    )

    @Test func committedWritePingsChanges() async throws {
        let store = try SwiftDataStore.inMemory()
        // Subscribe before writing so the continuation exists when the commit
        // fires; the stream buffers the newest ping, so iterating after still
        // sees it.
        let stream = store.changes()

        try await store.perform { try await store.setManualDay(day) }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    @Test func nestedPerformStillPingsOnCommit() async throws {
        let store = try SwiftDataStore.inMemory()
        let stream = store.changes()

        // A nested `perform` reuses the in-flight transaction; only the
        // outermost commit pings, so the consumer still gets its signal.
        try await store.perform {
            try await store.perform { try await store.setManualDay(day) }
        }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    @Test func rolledBackWriteDoesNotPingChanges() async throws {
        let store = try SwiftDataStore.inMemory()
        let stream = store.changes()

        // A throwing transaction discards the peer context without saving, so
        // nothing reaches the persistent store and no ping should fire.
        await #expect(throws: CancellationError.self) {
            try await store.perform {
                try await store.setManualDay(self.day)
                throw CancellationError()
            }
        }

        #expect(await !firstPing(stream, within: .milliseconds(200)))
    }
}

/// Awaits the first `changes()` ping, returning `false` if none arrives within
/// `budget`. Races the stream against a timeout so a missing ping fails fast
/// instead of hanging the test.
private func firstPing(_ stream: AsyncStream<Void>, within budget: Duration) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: budget)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
