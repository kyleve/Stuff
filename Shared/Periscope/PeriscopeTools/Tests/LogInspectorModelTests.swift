import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct LogInspectorModelTests {
    @Test func collectsSubtreeEventsNewestFirst() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("elsewhere", date: date(1), scopes: [root.id]),
            makeRecord("at photos", date: date(2), scopes: [photos.id]),
            makeRecord("in the album", date: date(3), scopes: [album.id]),
        ])

        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id])
        await model.load()

        #expect(model.events.map(\.message) == ["in the album", "at photos"])
    }

    @Test func mergesEventsAcrossLinkedScopes() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        let screen = LogScope.root(named: "detail-screen")
        await store.defineScopes([screen])
        await store.write([
            makeRecord("model side", date: date(1), scopes: [album.id]),
            makeRecord("ui side", date: date(2), scopes: [screen.id]),
        ])

        let model = LogInspectorModel(
            store: store,
            inspectedScopes: [photos.id, screen.id],
        )
        await model.load()

        #expect(model.events.map(\.message) == ["ui side", "model side"])
    }

    @Test func emptyScopesLoadAsEmpty() async throws {
        let (store, _, photos, _) = try await makeSeededStore()
        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id])
        await model.load()
        #expect(model.events.isEmpty)
        if case .failed = model.state {
            Issue.record("An empty subtree should load as empty, not fail")
        }
    }

    @Test func runRefreshesLiveWhenTheStoreCommits() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id])
        let task = Task { await model.run() }
        defer { task.cancel() }

        await store.write([makeRecord("live", date: date(1), scopes: [album.id])])
        let shown = await waitUntil { model.events.map(\.message) == ["live"] }
        #expect(shown)
    }

    @Test func scopePathsResolve() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([makeRecord("deep", date: date(1), scopes: [album.id])])

        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id])
        await model.load()

        let event = try #require(model.events.first)
        #expect(model.scopePath(for: event) == "app / photos / album-1")
    }
}
