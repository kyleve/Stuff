import Foundation
@_spi(Testing) import PeriscopeCore
import Testing
@testable import WhereUI

/// Covers `LogHistoryPruner`: that both retention bounds are enforced, that they
/// report separately, and that the shipped policy is bounded on both axes.
struct LogHistoryPrunerTests {
    /// A pinned "now" so the age window is exercised against fixed dates rather
    /// than the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    /// Windows are set to half-days so no seeded event lands exactly on the
    /// cutoff — where it's kept, since the store drops events strictly *older*
    /// than the cutoff. Which side of that edge a same-instant event falls on
    /// isn't what these tests are about.
    private static func days(_ count: Double) -> TimeInterval {
        count * 24 * 60 * 60
    }

    private func makeStore() async throws -> (store: PeriscopeStore, root: LogScope) {
        let store = try await PeriscopeStore.inMemory(session: .current())
        let root = LogScope.root(named: "app")
        await store.defineScopes([root])
        return (store, root)
    }

    /// Seed `count` events, the newest at `Self.now` and each earlier one a day
    /// further back.
    private func seedDays(
        _ count: Int,
        in store: PeriscopeStore,
        under root: LogScope,
    ) async {
        await store.write((0 ..< count).map { daysAgo in
            LogRecord(
                date: Self.now.addingTimeInterval(-Self.days(Double(daysAgo))),
                event: Message(level: .info, "day-\(daysAgo)"),
                scopes: [root.id],
            )
        })
    }

    private func pruner(window: TimeInterval, eventLimit: Int) -> LogHistoryPruner {
        LogHistoryPruner(
            policy: LogHistoryPruner.Policy(window: window, eventLimit: eventLimit),
            now: { Self.now },
        )
    }

    private func remainingMessages(in store: PeriscopeStore) async throws -> [String] {
        try await store.events(matching: LogQuery()).map(\.message)
    }

    @Test func dropsEventsPastTheWindow() async throws {
        let (store, root) = try await makeStore()
        await seedDays(5, in: store, under: root)

        // A limit far above what's stored, so only the window can bite.
        let outcome = try await pruner(window: Self.days(2.5), eventLimit: 1000).prune(store)

        #expect(outcome == LogHistoryPruner.Outcome(expired: 2, overflowed: 0))
        #expect(try await remainingMessages(in: store) == ["day-0", "day-1", "day-2"])
    }

    /// The point of the size cap: a device that logs heavily enough to fill the
    /// store *inside* the window is still bounded.
    @Test func capsTheCountEvenWhenEveryEventIsInsideTheWindow() async throws {
        let (store, root) = try await makeStore()
        await seedDays(5, in: store, under: root)

        // A window wide enough to keep all five, so only the cap can bite.
        let outcome = try await pruner(window: Self.days(365), eventLimit: 2).prune(store)

        #expect(outcome == LogHistoryPruner.Outcome(expired: 0, overflowed: 3))
        // Newest survive: history is trimmed from the far end, not the near one.
        #expect(try await remainingMessages(in: store) == ["day-0", "day-1"])
    }

    /// The counts are reported separately so a reader can tell routine expiry
    /// from an install being held to the cap — that distinction only holds if the
    /// cap counts what survived the window rather than everything it would have
    /// removed on its own.
    @Test func attributesEachRemovalToTheBoundThatMadeIt() async throws {
        let (store, root) = try await makeStore()
        await seedDays(6, in: store, under: root)

        let outcome = try await pruner(window: Self.days(3.5), eventLimit: 2).prune(store)

        // Days 5 and 4 expired; of the four that survived, the cap took two.
        #expect(outcome == LogHistoryPruner.Outcome(expired: 2, overflowed: 2))
        #expect(try await remainingMessages(in: store) == ["day-0", "day-1"])
    }

    @Test func reportsNothingRemovedWhenHistoryIsWithinBothBounds() async throws {
        let (store, root) = try await makeStore()
        await seedDays(3, in: store, under: root)

        let outcome = try await pruner(window: Self.days(365), eventLimit: 1000).prune(store)

        #expect(outcome == LogHistoryPruner.Outcome(expired: 0, overflowed: 0))
        #expect(try await remainingMessages(in: store).count == 3)
    }

    /// Either bound left open would let the store grow without limit on some
    /// device — a quiet one past the window, a chatty one within it.
    @Test func theShippedPolicyBoundsBothAxes() {
        #expect(LogHistoryPruner.Policy.standard.window == Self.days(100))
        #expect(LogHistoryPruner.Policy.standard.eventLimit > 0)
        #expect(LogHistoryPruner.Policy.standard.eventLimit < .max)
    }
}
