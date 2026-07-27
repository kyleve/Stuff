import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct LogHierarchyModelTests {
    @Test func buildsTheScopeForestWithNestingAndCounts() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("a", date: date(1), scopes: [root.id]),
            makeRecord("b", date: date(2), scopes: [photos.id]),
            makeRecord("c", date: date(3), scopes: [album.id]),
            makeRecord("d", date: date(4), scopes: [album.id]),
        ])

        let model = LogHierarchyModel(store: store)
        await model.load()

        guard case let .loaded(forest) = model.state else {
            Issue.record("Expected a loaded forest, got \(model.state)")
            return
        }

        // One root ("app"), holding photos, holding album-1.
        #expect(forest.map(\.name) == ["app"])
        let appNode = try #require(forest.first)
        #expect(appNode.directCount == 1)
        #expect(appNode.subtreeCount == 4)

        let photosNode = try #require(appNode.children?.first)
        #expect(photosNode.name == "photos")
        #expect(photosNode.directCount == 1)
        #expect(photosNode.subtreeCount == 3)

        let albumNode = try #require(photosNode.children?.first)
        #expect(albumNode.name == "album-1")
        #expect(albumNode.directCount == 2)
        #expect(albumNode.subtreeCount == 2)
        #expect(albumNode.children == nil)
    }

    @Test func sortsSiblingScopesByName() {
        let root = LogScope.root(named: "root")
        let zed = root.child(named: "zed")
        let alpha = root.child(named: "alpha")

        let forest = LogHierarchyModel.buildForest(
            scopes: [root, zed, alpha],
            directCounts: [:],
        )

        #expect(forest.map(\.name) == ["root"])
        #expect(forest.first?.children?.map(\.name) == ["alpha", "zed"])
    }

    @Test func treatsScopesWithMissingParentsAsRoots() {
        let orphanParent = LogScope.root(named: "ghost")
        let child = orphanParent.child(named: "child")

        // Only the child is present — its parent isn't in the set.
        let forest = LogHierarchyModel.buildForest(scopes: [child], directCounts: [:])

        #expect(forest.map(\.name) == ["child"])
        #expect(forest.first?.children == nil)
    }

    @Test func countsOnlyThePrimaryScope() throws {
        let root = LogScope.root(named: "root")
        let child = root.child(named: "child")
        let stored = StoredLogEvent(
            id: UUID(),
            date: date(1),
            sequence: 0,
            level: .info,
            eventName: "message",
            eventVersion: 1,
            message: "linked",
            payload: Data(),
            // Primary is child; root is a linked secondary scope.
            scopes: [child.id, root.id],
            tags: [],
            spanID: nil,
            spanExitMode: nil,
            callSite: nil,
            externalID: nil,
            attachments: [],
            sessionID: UUID(),
        )

        let forest = LogHierarchyModel.buildForest(
            scopes: [root, child],
            directCounts: LogHierarchyModel.directCounts(in: [stored]),
        )

        let rootNode = try #require(forest.first)
        #expect(rootNode.directCount == 0)
        #expect(rootNode.subtreeCount == 1)
        #expect(rootNode.children?.first?.directCount == 1)
    }

    @Test func liveRefreshesWhenTheStoreCommits() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = LogHierarchyModel(store: store)

        let running = Task { await model.run() }
        defer { running.cancel() }

        _ = await waitUntil {
            if case .loaded = model.state { return true }
            return false
        }

        await store.write([makeRecord("late", date: date(1), scopes: [root.id])])

        let updated = await waitUntil {
            guard case let .loaded(forest) = model.state else { return false }
            return forest.first?.subtreeCount == 1
        }
        #expect(updated)
    }

    /// Counts accumulate across successive commits and never double-count:
    /// each refresh only folds in events newer than the last one merged, so
    /// two batches of 2 and 3 total 5 — not 2 + 5, and not just the latest 3.
    @Test func accumulatesCountsAcrossCommitsWithoutDoubleCounting() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = LogHierarchyModel(store: store)

        let running = Task { await model.run() }
        defer { running.cancel() }

        await store.write([
            makeRecord("a", date: date(1), scopes: [root.id]),
            makeRecord("b", date: date(2), scopes: [root.id]),
        ])
        _ = await waitUntil {
            guard case let .loaded(forest) = model.state else { return false }
            return forest.first?.subtreeCount == 2
        }

        await store.write([
            makeRecord("c", date: date(3), scopes: [root.id]),
            makeRecord("d", date: date(4), scopes: [root.id]),
            makeRecord("e", date: date(5), scopes: [root.id]),
        ])
        let total = await waitUntil {
            guard case let .loaded(forest) = model.state else { return false }
            return forest.first?.subtreeCount == 5
        }
        #expect(total)
    }

    /// A scope whose parent was never defined is surfaced as a root live, and
    /// its events still count — the missing-parent handling isn't only a
    /// static `buildForest` concern.
    @Test func liveTreatsAScopeWithAMissingParentAsARoot() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())
        let ghost = LogScope.root(named: "ghost")
        let child = ghost.child(named: "child")
        // Only the child is defined — its parent isn't in the store.
        await store.defineScopes([child])

        let model = LogHierarchyModel(store: store)
        let running = Task { await model.run() }
        defer { running.cancel() }

        await store.write([makeRecord("orphaned", date: date(1), scopes: [child.id])])

        let shown = await waitUntil {
            guard case let .loaded(forest) = model.state else { return false }
            return forest.map(\.name) == ["child"]
                && forest.first?.subtreeCount == 1
                && forest.first?.children == nil
        }
        #expect(shown)
    }

    /// Restarting `run()` (e.g. the view reappears) re-loads over events
    /// already merged, but the sequence-filtered merge is idempotent: counts
    /// reflect the true total, never doubled.
    @Test func restartingRunDoesNotDoubleCount() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = LogHierarchyModel(store: store)

        let first = Task { await model.run() }
        await store.write([
            makeRecord("a", date: date(1), scopes: [root.id]),
            makeRecord("b", date: date(2), scopes: [root.id]),
        ])
        _ = await waitUntil {
            guard case let .loaded(forest) = model.state else { return false }
            return forest.first?.subtreeCount == 2
        }
        first.cancel()

        // Restart the live loop on the same model, then commit one more event.
        let second = Task { await model.run() }
        defer { second.cancel() }
        await store.write([makeRecord("c", date: date(3), scopes: [root.id])])

        let total = await waitUntil {
            guard case let .loaded(forest) = model.state else { return false }
            return forest.first?.subtreeCount == 3
        }
        #expect(total)
    }
}
