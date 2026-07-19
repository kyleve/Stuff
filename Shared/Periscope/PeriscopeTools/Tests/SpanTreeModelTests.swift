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
        #expect(outerNode.duration == .seconds(3))
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
        #expect(openNode.duration == nil)
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
            return !node.isOpen && node.duration == .seconds(1)
        }
        #expect(closed)
    }
}
