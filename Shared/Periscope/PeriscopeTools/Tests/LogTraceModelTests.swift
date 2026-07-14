import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct LogTraceModelTests {
    private func originEvent(in store: PeriscopeStore) async throws -> StoredLogEvent {
        try #require(try await store.events(matching: LogQuery()).first)
    }

    @Test func traceCollectsEarlierEventsInTheSameScopeNewestFirst() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        await store.write([
            makeRecord("earlier", date: date(1), scopes: [album.id]),
            makeRecord("later", date: date(2), scopes: [album.id]),
            makeRecord("origin error", level: .error, date: date(3), scopes: [album.id]),
            makeRecord("after the origin", date: date(4), scopes: [album.id]),
        ])
        let origin = try await originEvent(in: store)
        #expect(origin.message == "after the origin")

        // Trace from the error, not the newest event.
        let error = try #require(try await store.events(matching: LogQuery())
            .first { $0.message == "origin error" })
        let model = LogTraceModel(store: store, origin: error, limit: 500)
        await model.load()

        #expect(model.trail.map(\.message) == ["later", "earlier"])
    }

    @Test func traceWalksUpAncestorsButNotIntoSiblings() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        let sibling = photos.child(named: "album-2")
        await store.defineScopes([sibling])
        await store.write([
            makeRecord("at root", date: date(1), scopes: [root.id]),
            makeRecord("at photos", date: date(2), scopes: [photos.id]),
            makeRecord("in the sibling", date: date(3), scopes: [sibling.id]),
            makeRecord("origin", level: .error, date: date(4), scopes: [album.id]),
        ])
        let origin = try await originEvent(in: store)
        let model = LogTraceModel(store: store, origin: origin, limit: 500)
        await model.load()

        #expect(model.trail.map(\.message) == ["at photos", "at root"])
    }

    @Test func traceFollowsLinkedScopes() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        let screen = LogScope.root(named: "detail-screen")
        await store.defineScopes([screen])
        await store.write([
            makeRecord("ui context", date: date(1), scopes: [screen.id]),
            makeRecord("origin", level: .error, date: date(2), scopes: [album.id, screen.id]),
        ])
        let origin = try await originEvent(in: store)
        let model = LogTraceModel(store: store, origin: origin, limit: 500)
        await model.load()

        #expect(model.trail.map(\.message) == ["ui context"])
    }

    @Test func traceIncludesTheOriginsSpanPair() async throws {
        let (store, root, _, album) = try await makeSeededStore()
        let span = SpanID()
        await store.write([
            LogRecord(
                date: date(1),
                event: SpanBegan(
                    spanID: span,
                    name: "save",
                    lifetime: .indefinite,
                    relaunchPolicy: .endsWithProcess,
                ),
                scopes: [root.id],
            ),
            LogRecord(
                date: date(2),
                event: SpanEnded(
                    spanID: span,
                    name: "save",
                    duration: .seconds(1),
                    exit: .success,
                ),
                scopes: [album.id],
            ),
        ])
        let origin = try await originEvent(in: store)
        #expect(origin.spanID == span)

        let model = LogTraceModel(store: store, origin: origin, limit: 500)
        await model.load()

        #expect(model.trail.contains { $0.spanID == span && $0.eventName == "span-began" })
    }

    @Test func sameMillisecondEventsAfterTheOriginAreExcluded() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        let sharedInstant = date(5)
        await store.write([
            makeRecord("before", date: sharedInstant, scopes: [album.id]),
            makeRecord("origin", level: .error, date: sharedInstant, scopes: [album.id]),
            makeRecord("after", date: sharedInstant, scopes: [album.id]),
        ])
        let origin = try #require(try await store.events(matching: LogQuery())
            .first { $0.message == "origin" })

        let model = LogTraceModel(store: store, origin: origin, limit: 500)
        await model.load()

        #expect(model.trail.map(\.message) == ["before"])
    }

    @Test func traceExcludesTheOriginItself() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        await store.write([makeRecord("origin", date: date(1), scopes: [album.id])])
        let origin = try await originEvent(in: store)

        let model = LogTraceModel(store: store, origin: origin, limit: 500)
        await model.load()

        #expect(model.trail.isEmpty)
    }

    @Test func scopePathsResolveForTrailRows() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("context", date: date(1), scopes: [photos.id]),
            makeRecord("origin", date: date(2), scopes: [album.id]),
        ])
        let origin = try await originEvent(in: store)
        let model = LogTraceModel(store: store, origin: origin, limit: 500)
        await model.load()

        let context = try #require(model.trail.first)
        #expect(model.scopePath(for: context) == "app / photos")
    }
}
