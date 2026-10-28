import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct SpanTreeModelTests {
    /// A began/ended pair opening and closing entirely within another's
    /// lifetime nests under it; independent spans stay at the root.
    @Test func nestsSpansByTimeContainment() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let outer = SpanID()
        let inner = SpanID()
        let sibling = SpanID()
        await store.write([
            spanBegan(outer, name: "outer", at: date(0), scope: root.id),
            spanBegan(inner, name: "inner", at: date(1), scope: root.id),
            spanEnded(inner, name: "inner", at: date(2), duration: .seconds(1), scope: root.id),
            spanEnded(outer, name: "outer", at: date(3), duration: .seconds(3), scope: root.id),
            spanBegan(sibling, name: "sibling", at: date(4), scope: root.id),
            spanEnded(sibling, name: "sibling", at: date(5), duration: .seconds(1), scope: root.id),
        ])

        let model = SpanTreeModel(store: store)
        await model.load()

        guard case let .loaded(tree) = model.state else {
            Issue.record("Expected a loaded tree, got \(model.state)")
            return
        }

        #expect(tree.map(\.name) == ["outer", "sibling"])
        let outerNode = try #require(tree.first)
        #expect(outerNode.children?.map(\.name) == ["inner"])
        #expect(outerNode.measuredDuration == .seconds(3))
        #expect(outerNode.exitMode == .success)
        #expect(tree.last?.children == nil)
    }

    @Test func pairsExitModeAndLeavesUnendedSpansOpen() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let failed = SpanID()
        let open = SpanID()
        await store.write([
            spanBegan(failed, name: "failed", at: date(0), scope: root.id),
            spanEnded(
                failed,
                name: "failed",
                at: date(1),
                duration: .seconds(1),
                exit: SpanExit(mode: .failure, reason: "boom"),
                scope: root.id,
            ),
            spanBegan(open, name: "open", at: date(2), scope: root.id),
        ])

        let model = SpanTreeModel(store: store)
        await model.load()

        guard case let .loaded(tree) = model.state else {
            Issue.record("Expected a loaded tree, got \(model.state)")
            return
        }

        let failedNode = try #require(tree.first { $0.name == "failed" })
        #expect(failedNode.exitMode == .failure)
        #expect(!failedNode.isOpen)

        let openNode = try #require(tree.first { $0.name == "open" })
        #expect(openNode.isOpen)
        #expect(openNode.exitMode == nil)
        #expect(openNode.measuredDuration == nil)
    }

    /// A span whose end coincides with the next span's begin is a sibling,
    /// not a child — the containment stack pops on `<=`, so touching spans
    /// don't nest.
    @Test func endAdjacentToTheNextBeginStaysASibling() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let first = SpanID()
        let second = SpanID()
        await store.write([
            spanBegan(first, name: "first", at: date(0), scope: root.id),
            spanEnded(first, name: "first", at: date(1), duration: .seconds(1), scope: root.id),
            // Begins exactly when `first` ended.
            spanBegan(second, name: "second", at: date(1), scope: root.id),
            spanEnded(second, name: "second", at: date(2), duration: .seconds(1), scope: root.id),
        ])

        let model = SpanTreeModel(store: store)
        await model.load()

        guard case let .loaded(tree) = model.state else {
            Issue.record("Expected a loaded tree, got \(model.state)")
            return
        }
        #expect(tree.map(\.name) == ["first", "second"])
        #expect(tree.allSatisfy { $0.children == nil })
    }

    /// A `SpanEnded` with no matching `SpanBegan` (e.g. its begin was pruned
    /// or dropped) is ignored rather than appearing as a phantom node.
    @Test func ignoresAnEndWithoutAMatchingBegin() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let real = SpanID()
        let orphanEnd = SpanID()
        await store.write([
            spanBegan(real, name: "real", at: date(0), scope: root.id),
            spanEnded(real, name: "real", at: date(1), duration: .seconds(1), scope: root.id),
            spanEnded(orphanEnd, name: "ghost", at: date(2), duration: .seconds(1), scope: root.id),
        ])

        let model = SpanTreeModel(store: store)
        await model.load()

        guard case let .loaded(tree) = model.state else {
            Issue.record("Expected a loaded tree, got \(model.state)")
            return
        }
        #expect(tree.map(\.name) == ["real"])
    }

    // MARK: - Unreadable payloads

    /// The exit comes from an indexed column and the duration from the payload,
    /// so a corrupt payload used to render an exit chip beside a "running"
    /// duration. A span that ended can only describe itself as ended.
    @Test func anEndWithAnUnreadablePayloadNeverReadsAsRunning() throws {
        let id = SpanID()
        let tree = try SpanTreeModel.buildTree(
            begins: [storedSpanBegan(id, name: "save", at: date(0))],
            ends: [
                storedSpanEvent(
                    eventName: SpanEnded.eventName,
                    spanID: id,
                    message: "◀ save",
                    at: date(1),
                    payload: unreadablePayload,
                    exitMode: .success,
                ),
            ],
        )

        let node = try #require(tree.first)
        #expect(!node.isOpen)
        #expect(node.exitMode == .success)
        guard case let .ended(ended) = node.outcome else {
            Issue.record("Expected an ended span, got \(node.outcome)")
            return
        }
        #expect(ended.timing == .undecodable)
    }

    /// An orphan closed by the relaunch sweep records no duration. That's a
    /// different fact from a payload that wouldn't decode, and the two must not
    /// collapse into one reading.
    @Test func anEndWithoutADurationReadsAsUnmeasuredNotUnreadable() throws {
        let id = SpanID()
        let tree = try SpanTreeModel.buildTree(
            begins: [storedSpanBegan(id, name: "save", at: date(0))],
            ends: [
                storedSpanEnded(id, name: "save", at: date(1), duration: nil, exit: .orphaned),
            ],
        )

        guard case let .ended(ended) = try #require(tree.first).outcome else {
            Issue.record("Expected an ended span")
            return
        }
        #expect(ended.timing == .unmeasured)
    }

    /// A began whose payload won't decode still shows up — named from its
    /// message, with the span-began marker stripped.
    @Test func namesASpanFromItsMessageWhenTheBeganPayloadIsUnreadable() throws {
        let id = SpanID()
        let tree = SpanTreeModel.buildTree(
            begins: [
                storedSpanEvent(
                    eventName: SpanBegan.eventName,
                    spanID: id,
                    message: "▶ save",
                    at: date(0),
                    payload: unreadablePayload,
                ),
            ],
            ends: [],
        )

        #expect(tree.map(\.name) == ["save"])
        #expect(try #require(tree.first).isOpen)
    }

    @Test func loadsEmptyWhenNoSpansRecorded() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([makeRecord("not a span", date: date(0), scopes: [root.id])])

        let model = SpanTreeModel(store: store)
        await model.load()

        guard case let .loaded(tree) = model.state else {
            Issue.record("Expected a loaded (empty) tree, got \(model.state)")
            return
        }
        #expect(tree.isEmpty)
    }

    @Test func liveRefreshesWhenTheStoreCommits() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = SpanTreeModel(store: store)

        let running = Task { await model.run() }
        defer { running.cancel() }

        _ = await waitUntil {
            if case .loaded = model.state { return true }
            return false
        }

        let span = SpanID()
        await store.write([
            spanBegan(span, name: "late", at: date(0), scope: root.id),
            spanEnded(span, name: "late", at: date(1), duration: .seconds(1), scope: root.id),
        ])

        let shown = await waitUntil {
            guard case let .loaded(tree) = model.state else { return false }
            return tree.map(\.name) == ["late"]
        }
        #expect(shown)
    }

    /// A span's end usually lands in a later commit than its begin. The begin
    /// shows open first; when the end arrives in a subsequent refresh, the
    /// incrementally-fetched end pairs with the already-accumulated begin —
    /// the span flips to ended without re-reading the whole store.
    @Test func pairsAnEndArrivingInALaterCommit() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = SpanTreeModel(store: store)

        let running = Task { await model.run() }
        defer { running.cancel() }

        let span = SpanID()
        await store.write([spanBegan(span, name: "work", at: date(0), scope: root.id)])
        let opened = await waitUntil {
            guard case let .loaded(tree) = model.state else { return false }
            return tree.first?.name == "work" && tree.first?.isOpen == true
        }
        #expect(opened)

        await store.write([
            spanEnded(span, name: "work", at: date(1), duration: .seconds(1), scope: root.id),
        ])
        let closed = await waitUntil {
            guard case let .loaded(tree) = model.state else { return false }
            guard tree.count == 1, let node = tree.first else { return false }
            return !node.isOpen && node.measuredDuration == .seconds(1)
        }
        #expect(closed)
    }

    /// Restarting `run()` re-loads over spans already accumulated, but the
    /// sequence-filtered merge is idempotent: a span isn't listed twice.
    @Test func restartingRunDoesNotDuplicateSpans() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = SpanTreeModel(store: store)

        let first = Task { await model.run() }
        let a = SpanID()
        await store.write([
            spanBegan(a, name: "a", at: date(0), scope: root.id),
            spanEnded(a, name: "a", at: date(1), duration: .seconds(1), scope: root.id),
        ])
        _ = await waitUntil {
            guard case let .loaded(tree) = model.state else { return false }
            return tree.map(\.name) == ["a"]
        }
        first.cancel()

        let second = Task { await model.run() }
        defer { second.cancel() }
        let b = SpanID()
        await store.write([
            spanBegan(b, name: "b", at: date(2), scope: root.id),
            spanEnded(b, name: "b", at: date(3), duration: .seconds(1), scope: root.id),
        ])

        let both = await waitUntil {
            guard case let .loaded(tree) = model.state else { return false }
            return tree.map(\.name) == ["a", "b"]
        }
        #expect(both)
    }
}
