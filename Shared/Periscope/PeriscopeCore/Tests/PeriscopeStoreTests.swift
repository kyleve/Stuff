import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

struct PeriscopeStoreTests {
    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }

    /// A store with a small defined hierarchy: app → photos → album-1.
    private func makeStore() async throws -> (
        store: PeriscopeStore,
        root: LogScope,
        photos: LogScope,
        album: LogScope
    ) {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let root = LogScope.root(named: "app")
        let photos = root.child(named: "photos")
        let album = photos.child(named: "album-1")
        await store.defineScopes([root, photos, album])
        return (store, root, photos, album)
    }

    @Test func eventsComeBackNewestFirst() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("first", date: date(1), scopes: [root.id]),
            makeRecord("second", date: date(2), scopes: [root.id]),
            makeRecord("third", date: date(3), scopes: [root.id]),
        ])

        let events = try await store.events(matching: LogQuery())
        #expect(events.map(\.message) == ["third", "second", "first"])
    }

    @Test func payloadsDecodeBackToTheirEventTypes() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            LogRecord(date: date(1), event: PhotoLogs(photoID: "p1"), scopes: [root.id]),
        ])

        let event = try #require(try await store.events(matching: LogQuery()).first)
        #expect(event.eventName == "PhotoLogs")
        #expect(event.eventVersion == 1)
        #expect(try event.decode(PhotoLogs.self).photoID == "p1")
    }

    @Test func minimumLevelFiltersBySeverity() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("d", level: .debug, date: date(1), scopes: [root.id]),
            makeRecord("w", level: .warning, date: date(2), scopes: [root.id]),
            makeRecord("e", level: .error, date: date(3), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.minimumLevel = .warning
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["e", "w"])
    }

    @Test func customLevelsRoundTripThroughStorage() async throws {
        let (store, root, _, _) = try await makeStore()
        let audit = LogLevel(name: "audit", severity: 450)
        await store.write([makeRecord("a", level: audit, date: date(1), scopes: [root.id])])

        let event = try #require(try await store.events(matching: LogQuery()).first)
        #expect(event.level == audit)
    }

    @Test func timeRangeFilters() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("early", date: date(10), scopes: [root.id]),
            makeRecord("mid", date: date(20), scopes: [root.id]),
            makeRecord("late", date: date(30), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.start = date(15)
        query.end = date(25)
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["mid"])
    }

    @Test func eventNameFilters() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("plain", date: date(1), scopes: [root.id]),
            LogRecord(date: date(2), event: PhotoLogs(photoID: "p1"), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.eventName = PhotoLogs.eventName
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["photo p1"])
    }

    @Test func sessionFilters() async throws {
        let (store, root, _, _) = try await makeStore()
        let firstSession = LogSession.fixture()
        try await store.startSession(firstSession)
        await store.write([makeRecord("in first", date: date(1), scopes: [root.id])])

        let secondSession = LogSession.fixture(startedAt: date(100))
        try await store.startSession(secondSession)
        await store.write([makeRecord("in second", date: date(101), scopes: [root.id])])

        var query = LogQuery()
        query.sessionID = firstSession.id
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["in first"])
    }

    @Test func messageSearchFilters() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("Uploading photo", date: date(1), scopes: [root.id]),
            makeRecord("Deleting album", date: date(2), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.messageContains = "photo"
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["Uploading photo"])
    }

    @Test func exactScopeFilters() async throws {
        let (store, root, photos, album) = try await makeStore()
        await store.write([
            makeRecord("at root", date: date(1), scopes: [root.id]),
            makeRecord("at photos", date: date(2), scopes: [photos.id]),
            makeRecord("at album", date: date(3), scopes: [album.id]),
        ])

        var query = LogQuery()
        query.scope = photos.id
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["at photos"])
    }

    @Test func subtreeFiltersIncludeDescendants() async throws {
        let (store, root, photos, album) = try await makeStore()
        await store.write([
            makeRecord("at root", date: date(1), scopes: [root.id]),
            makeRecord("at photos", date: date(2), scopes: [photos.id]),
            makeRecord("at album", date: date(3), scopes: [album.id]),
        ])

        var query = LogQuery()
        query.subtree = photos.id
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["at album", "at photos"])
    }

    @Test func linkedEventsMatchEitherScope() async throws {
        let (store, root, photos, _) = try await makeStore()
        await store.write([
            makeRecord("linked", date: date(1), scopes: [photos.id, root.id]),
        ])

        var byRoot = LogQuery()
        byRoot.scope = root.id
        var byPhotos = LogQuery()
        byPhotos.scope = photos.id

        #expect(try await store.events(matching: byRoot).count == 1)
        #expect(try await store.events(matching: byPhotos).count == 1)

        let stored = try #require(try await store.events(matching: LogQuery()).first)
        #expect(stored.scopes == [photos.id, root.id])
    }

    @Test func limitAndOffsetPageNewestFirst() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write((1 ... 5).map { index in
            makeRecord("\(index)", date: date(TimeInterval(index)), scopes: [root.id])
        })

        var page = LogQuery()
        page.limit = 2
        #expect(try await store.events(matching: page).map(\.message) == ["5", "4"])

        page.offset = 2
        #expect(try await store.events(matching: page).map(\.message) == ["3", "2"])
    }

    @Test func scopeDefinitionsAreIdempotent() async throws {
        let (store, root, photos, album) = try await makeStore()
        await store.defineScopes([root, photos, album])

        let scopes = try await store.scopes()
        #expect(scopes.count == 3)
        #expect(try await store.scope(for: photos.id) == photos)
    }

    @Test func lateScopeDefinitionsFillPlaceholders() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let orphan = LogScope.root(named: "late")
        await store.write([makeRecord("early", date: date(1), scopes: [orphan.id])])

        let placeholder = try #require(try await store.scope(for: orphan.id))
        #expect(placeholder.name.isEmpty)

        await store.defineScopes([orphan])
        #expect(try await store.scope(for: orphan.id) == orphan)
        #expect(try await store.events(matching: LogQuery()).count == 1)
    }

    @Test func pruneOlderThanRemovesOnlyOldEvents() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("old", date: date(1), scopes: [root.id]),
            makeRecord("new", date: date(100), scopes: [root.id]),
        ])

        let removed = try await store.pruneEvents(olderThan: date(50))
        #expect(removed == 1)
        #expect(try await store.events(matching: LogQuery()).map(\.message) == ["new"])
    }

    @Test func pruneKeepingNewestKeepsTheCount() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write((1 ... 5).map { index in
            makeRecord("\(index)", date: date(TimeInterval(index)), scopes: [root.id])
        })

        let removed = try await store.pruneEvents(keepingNewest: 2)
        #expect(removed == 3)
        #expect(try await store.events(matching: LogQuery()).map(\.message) == ["5", "4"])
    }

    @Test func deleteAllEventsClearsTheStore() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([makeRecord("gone", date: date(1), scopes: [root.id])])

        try await store.deleteAllEvents()
        #expect(try await store.events(matching: LogQuery()).isEmpty)
    }

    @Test func changesPingOnWritesAndDeletions() async throws {
        let (store, root, _, _) = try await makeStore()
        var iterator = await store.changes().makeAsyncIterator()

        await store.write([makeRecord("one", date: date(1), scopes: [root.id])])
        #expect(await iterator.next() != nil)

        try await store.deleteAllEvents()
        #expect(await iterator.next() != nil)
    }

    @Test func sessionsListNewestFirstWithMetadata() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture(startedAt: date(0)))
        let later = LogSession.fixture(startedAt: date(100))
        try await store.startSession(later)

        let sessions = try await store.sessions()
        #expect(sessions.count == 2)
        #expect(sessions.first == later)
        #expect(sessions.first?.appVersion == "1.0")
        #expect(sessions.first?.deviceModel == "TestDevice1,1")
    }

    @Test func eventByIDResolves() async throws {
        let (store, root, _, _) = try await makeStore()
        let record = makeRecord("target", date: date(1), scopes: [root.id])
        await store.write([record])

        let found = try #require(try await store.event(id: record.id))
        #expect(found.message == "target")
        #expect(try await store.event(id: UUID()) == nil)
    }

    @Test func endToEndThroughThePeriscopeSystem() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [store])
        let photos = Log<AppLogs>(system: system)(PhotoLogs.self)

        photos { PhotoLogs(photoID: "p1") }
        photos.warning("degraded")
        await system.flush()

        let events = try await store.events(matching: LogQuery())
        #expect(events.map(\.message) == ["degraded", "photo p1"])
        #expect(events.allSatisfy { $0.scopes == photos.scopes.map(\.id) })
        #expect(try await store.scope(for: photos.primaryScope.id)?.name == "PhotoLogs")
    }
}
