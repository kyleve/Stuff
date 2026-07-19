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

        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id], limit: 500)
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
            limit: 500,
        )
        await model.load()

        #expect(model.events.map(\.message) == ["ui side", "model side"])
    }

    @Test func emptyScopesLoadAsEmpty() async throws {
        let (store, _, photos, _) = try await makeSeededStore()
        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id], limit: 500)
        await model.load()
        #expect(model.events.isEmpty)
        if case .failed = model.state {
            Issue.record("An empty subtree should load as empty, not fail")
        }
    }

    @Test func runRefreshesLiveWhenTheStoreCommits() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id], limit: 500)
        let task = Task { await model.run() }
        defer { task.cancel() }

        await store.write([makeRecord("live", date: date(1), scopes: [album.id])])
        let shown = await waitUntil { model.events.map(\.message) == ["live"] }
        #expect(shown)
    }

    @Test func scopePathsResolve() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([makeRecord("deep", date: date(1), scopes: [album.id])])

        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id], limit: 500)
        await model.load()

        let event = try #require(model.events.first)
        #expect(model.scopePath(for: event) == "app / photos / album-1")
    }

    @Test func depthCountsScopesBelowTheViewedRoot() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("at photos", date: date(1), scopes: [photos.id]),
            makeRecord("in the album", date: date(2), scopes: [album.id]),
        ])

        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id], limit: 500)
        await model.load()

        let albumEvent = try #require(model.events.first { $0.message == "in the album" })
        let photosEvent = try #require(model.events.first { $0.message == "at photos" })
        // Viewed at `photos`: its own events sit at depth 0, album-1 one below.
        #expect(model.depth(of: photosEvent, below: photos.id) == 0)
        #expect(model.depth(of: albumEvent, below: photos.id) == 1)
    }

    @Test func depthClampsToZeroForEventsAtOrAboveTheViewedRoot() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("at photos", date: date(1), scopes: [photos.id]),
            makeRecord("at root", date: date(2), scopes: [root.id]),
        ])

        // View below the deep `album` scope; events living at `photos` or the
        // `root` (both above album) clamp to depth 0 rather than going
        // negative.
        let model = LogInspectorModel(store: store, inspectedScopes: [root.id], limit: 500)
        await model.load()

        let photosEvent = try #require(model.events.first { $0.message == "at photos" })
        let rootEvent = try #require(model.events.first { $0.message == "at root" })
        #expect(model.depth(of: photosEvent, below: album.id) == 0)
        #expect(model.depth(of: rootEvent, below: album.id) == 0)
    }

    @Test func depthIsZeroForAnEventWithoutAScope() async throws {
        let (store, _, photos, _) = try await makeSeededStore()
        let model = LogInspectorModel(store: store, inspectedScopes: [photos.id], limit: 500)
        await model.load()

        let scopeless = StoredLogEvent(
            id: UUID(),
            date: date(1),
            sequence: 0,
            level: .info,
            eventName: "message",
            eventVersion: 1,
            message: "no scope",
            payload: Data(),
            scopes: [],
            tags: [],
            spanID: nil,
            spanExitMode: nil,
            callSite: nil,
            externalID: nil,
            attachments: [],
            sessionID: UUID(),
        )
        #expect(model.depth(of: scopeless, below: photos.id) == 0)
    }
}
