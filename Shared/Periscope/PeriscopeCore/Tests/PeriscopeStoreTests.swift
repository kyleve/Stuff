import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

private struct InjectedSaveFailure: Error {}

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
        query.scope = .exactly(photos.id)
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
        query.scope = .subtree(photos.id)
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["at album", "at photos"])
    }

    @Test func linkedEventsMatchEitherScope() async throws {
        let (store, root, photos, _) = try await makeStore()
        await store.write([
            makeRecord("linked", date: date(1), scopes: [photos.id, root.id]),
        ])

        var byRoot = LogQuery()
        byRoot.scope = .exactly(root.id)
        var byPhotos = LogQuery()
        byPhotos.scope = .exactly(photos.id)

        #expect(try await store.events(matching: byRoot).count == 1)
        #expect(try await store.events(matching: byPhotos).count == 1)

        let stored = try #require(try await store.events(matching: LogQuery()).first)
        #expect(stored.scopes == [photos.id, root.id])
    }

    @Test func attachmentsPersistAndLoadOnDemand() async throws {
        let (store, root, _, _) = try await makeStore()
        let first = LogAttachment(name: "a", contentType: .plainText, data: Data([1]))
        let second = LogAttachment(name: "b", contentType: .png, data: Data([2, 3]))
        let record = LogRecord(
            date: date(1),
            event: Message(level: .error, "failed"),
            scopes: [root.id],
            attachments: [first, second],
        )
        await store.write([record, makeRecord("bare", date: date(2), scopes: [root.id])])

        let stored = try #require(try await store.events(matching: LogQuery())
            .first { $0.message == "failed" })
        #expect(stored.attachments == [
            LogAttachmentInfo(name: "a", contentType: .plainText),
            LogAttachmentInfo(name: "b", contentType: .png),
        ])

        let loaded = try await store.attachments(forEvent: record.id)
        #expect(loaded == [first, second])

        let bare = try #require(try await store.events(matching: LogQuery())
            .first { $0.message == "bare" })
        #expect(bare.attachments.isEmpty)
        #expect(try await store.attachments(forEvent: UUID()).isEmpty)
    }

    @Test func spanEventsResolveBySpanID() async throws {
        let (store, root, _, _) = try await makeStore()
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
            makeRecord("unrelated", date: date(2), scopes: [root.id]),
            LogRecord(
                date: date(3),
                event: SpanEnded(
                    spanID: span,
                    name: "save",
                    duration: .seconds(2),
                    exit: .success,
                ),
                scopes: [root.id],
            ),
        ])

        let pair = try await store.events(inSpan: span)
        #expect(pair.count == 2)
        #expect(pair.allSatisfy { $0.spanID == span })
        #expect(try pair.first.map { try $0.decode(SpanEnded.self).duration } == .seconds(2))

        let unrelated = try await store.events(matching: LogQuery())
            .first { $0.message == "unrelated" }
        #expect(unrelated?.spanID == nil)
    }

    @Test func spanExitModesPersistAndFilter() async throws {
        let (store, root, _, _) = try await makeStore()
        let failedSpan = SpanID()
        await store.write([
            LogRecord(
                date: date(1),
                event: SpanEnded(
                    spanID: failedSpan,
                    name: "save",
                    duration: .seconds(1),
                    exit: .failure("card declined"),
                ),
                scopes: [root.id],
            ),
            LogRecord(
                date: date(2),
                event: SpanEnded(
                    spanID: SpanID(),
                    name: "sync",
                    duration: .seconds(1),
                    exit: .success,
                ),
                scopes: [root.id],
            ),
            makeRecord("not a span", date: date(3), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.spanExitMode = .failure
        let failures = try await store.events(matching: query)
        #expect(failures.map(\.spanID) == [failedSpan])
        #expect(failures.first?.spanExitMode == .failure)

        let all = try await store.events(matching: LogQuery())
        #expect(all.first { $0.message == "not a span" }?.spanExitMode == nil)
    }

    // MARK: Orphaned spans

    private func writeSpanBegan(
        _ store: PeriscopeStore,
        span: SpanID,
        name: String,
        relaunch: SpanRelaunchPolicy,
        scope: LogScope,
        tags: [LogTag] = [],
    ) async {
        await store.write([
            LogRecord(
                date: date(1),
                event: SpanBegan(
                    spanID: span,
                    name: name,
                    lifetime: .indefinite,
                    relaunchPolicy: relaunch,
                ),
                scopes: [scope.id],
                tags: tags,
            ),
        ])
    }

    @Test func relaunchClosesOrphanedSpans() async throws {
        let (store, root, _, _) = try await makeStore()
        let span = SpanID()
        let key = LogTagKey("payment-id")
        await writeSpanBegan(
            store,
            span: span,
            name: "checkout",
            relaunch: .endsWithProcess,
            scope: root,
            tags: [LogTag(key: key, value: "pay_1")],
        )

        // A new session declares the earlier one dead.
        try await store.startSession(.fixture(startedAt: date(100)))

        let pair = try await store.events(inSpan: span)
        #expect(pair.count == 2)
        let orphanRow = try #require(pair.first { $0.eventName == SpanEnded.eventName })
        let orphan = try orphanRow.decode(SpanEnded.self)
        #expect(orphan.exit == .orphaned)
        #expect(orphan.duration == nil)
        #expect(orphan.name == "checkout")
        #expect(orphanRow.scopes == [root.id])
        #expect(orphanRow.tags == [LogTag(key: key, value: "pay_1")])
        #expect(orphanRow.level == .warning)
    }

    @Test func relaunchLeavesSurvivingSpansOpen() async throws {
        let (store, root, _, _) = try await makeStore()
        let span = SpanID()
        await writeSpanBegan(
            store,
            span: span,
            name: "long-download",
            relaunch: .survivesRelaunch,
            scope: root,
        )

        try await store.startSession(.fixture(startedAt: date(100)))

        let events = try await store.events(inSpan: span)
        #expect(events.count == 1)
        #expect(events.first?.eventName == SpanBegan.eventName)
    }

    @Test func relaunchIgnoresProperlyEndedSpans() async throws {
        let (store, root, _, _) = try await makeStore()
        let span = SpanID()
        await writeSpanBegan(
            store,
            span: span,
            name: "save",
            relaunch: .endsWithProcess,
            scope: root,
        )
        await store.write([
            LogRecord(
                date: date(2),
                event: SpanEnded(
                    spanID: span,
                    name: "save",
                    duration: .seconds(1),
                    exit: .success,
                ),
                scopes: [root.id],
            ),
        ])

        try await store.startSession(.fixture(startedAt: date(100)))

        let events = try await store.events(inSpan: span)
        #expect(events.count == 2)
        #expect(events.compactMap { try? $0.decode(SpanEnded.self) }.count == 1)
    }

    @Test func tagsPersistAndFilter() async throws {
        let (store, root, _, _) = try await makeStore()
        let key = LogTagKey("payment-id")
        await store.write([
            LogRecord(
                date: date(1),
                event: Message(level: .info, "for pay_1"),
                scopes: [root.id],
                tags: [LogTag(key: key, value: "pay_1")],
            ),
            LogRecord(
                date: date(2),
                event: Message(level: .info, "for pay_2"),
                scopes: [root.id],
                tags: [LogTag(key: key, value: "pay_2")],
            ),
            makeRecord("untagged", date: date(3), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.tags = [LogTag(key: key, value: "pay_1")]
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["for pay_1"])
        #expect(events.first?.tags == [LogTag(key: key, value: "pay_1")])

        let all = try await store.events(matching: LogQuery())
        #expect(all.first { $0.message == "untagged" }?.tags.isEmpty == true)
    }

    @Test func externalIDsPersistAndFilter() async throws {
        struct PhotoUploaded: LogEvent {
            var photoURI: String
            var message: String {
                "uploaded"
            }

            var externalID: String? {
                photoURI
            }
        }

        let (store, root, _, _) = try await makeStore()
        await store.write([
            LogRecord(
                date: date(1),
                event: PhotoUploaded(photoURI: "photos://p1"),
                scopes: [root.id],
            ),
            LogRecord(
                date: date(2),
                event: PhotoUploaded(photoURI: "photos://p2"),
                scopes: [root.id],
            ),
            makeRecord("no object", date: date(3), scopes: [root.id]),
        ])

        var query = LogQuery()
        query.externalID = "photos://p1"
        let events = try await store.events(matching: query)
        #expect(events.count == 1)
        #expect(events.first?.externalID == "photos://p1")

        let all = try await store.events(matching: LogQuery())
        #expect(all.first { $0.message == "no object" }?.externalID == nil)
    }

    @Test func callSitesPersistAndReadBack() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            LogRecord(
                date: date(1),
                event: Message(level: .info, "located"),
                scopes: [root.id],
                callSite: LogCallSite(function: "uploadPhoto(_:)", fileID: "App/Uploader.swift"),
            ),
            makeRecord("system-synthesized", date: date(2), scopes: [root.id]),
        ])

        let events = try await store.events(matching: LogQuery())
        let located = try #require(events.first { $0.message == "located" })
        #expect(located.callSite?.function == "uploadPhoto(_:)")
        #expect(located.callSite?.fileID == "App/Uploader.swift")
        #expect(events.first { $0.message == "system-synthesized" }?.callSite == nil)
    }

    @Test func multipleQueryTagsCombineWithAND() async throws {
        let (store, root, _, _) = try await makeStore()
        let payment = LogTagKey("payment-id")
        let retry = LogTagKey("retry")
        await store.write([
            LogRecord(
                date: date(1),
                event: Message(level: .info, "both"),
                scopes: [root.id],
                tags: [
                    LogTag(key: payment, value: "pay_1"),
                    LogTag(key: retry, value: .int(2)),
                ],
            ),
            LogRecord(
                date: date(2),
                event: Message(level: .info, "payment only"),
                scopes: [root.id],
                tags: [LogTag(key: payment, value: "pay_1")],
            ),
            LogRecord(
                date: date(3),
                event: Message(level: .info, "retry only"),
                scopes: [root.id],
                tags: [LogTag(key: retry, value: .int(2))],
            ),
        ])

        var query = LogQuery()
        query.tags = [
            LogTag(key: payment, value: "pay_1"),
            LogTag(key: retry, value: .int(2)),
        ]
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["both"])
    }

    @Test func typedTagValuesRoundTripAndStayDistinctFromStrings() async throws {
        let (store, root, _, _) = try await makeStore()
        let key = LogTagKey("retry")
        await store.write([
            LogRecord(
                date: date(1),
                event: Message(level: .info, "typed int"),
                scopes: [root.id],
                tags: [LogTag(key: key, value: .int(3))],
            ),
            LogRecord(
                date: date(2),
                event: Message(level: .info, "stringly"),
                scopes: [root.id],
                tags: [LogTag(key: key, value: .string("3"))],
            ),
        ])

        // The kind survives persistence: filtering by .int(3) must not
        // match .string("3"), and the read-back value stays typed.
        var query = LogQuery()
        query.tags = [LogTag(key: key, value: .int(3))]
        let events = try await store.events(matching: query)
        #expect(events.map(\.message) == ["typed int"])
        #expect(events.first?.tags[key] == .int(3))
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

    @Test func pruningRemovesOrphanedSessionsTagsAndScopes() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let root = LogScope.root(named: "app")
        let album = root.child(named: "album-1")
        let key = LogTagKey("payment-id")
        await store.defineScopes([root, album])
        await store.write([
            LogRecord(
                date: date(1),
                event: Message(level: .info, "old"),
                scopes: [album.id],
                tags: [LogTag(key: key, value: "pay_old")],
            ),
        ])

        // A later launch writes newer events under the root only.
        let liveSession = LogSession.fixture(startedAt: date(100))
        try await store.startSession(liveSession)
        await store.write([
            LogRecord(
                date: date(200),
                event: Message(level: .info, "new"),
                scopes: [root.id],
                tags: [LogTag(key: key, value: "pay_new")],
            ),
        ])

        #expect(try await store.pruneEvents(olderThan: date(50)) == 1)

        // The dead launch's session, the orphaned tag pair, and the
        // event-less album leaf are gone; root keeps its event, and the
        // live session survives.
        #expect(try await store.sessions().map(\.id) == [liveSession.id])
        #expect(try await store.scope(for: album.id) == nil)
        #expect(try await store.scope(for: root.id) == root)

        // A pruned tag pair is re-creatable — the row cache dropped its
        // deleted entry rather than handing back a dead row.
        await store.write([
            LogRecord(
                date: date(300),
                event: Message(level: .info, "old pair reused"),
                scopes: [root.id],
                tags: [LogTag(key: key, value: "pay_old")],
            ),
        ])
        var query = LogQuery()
        query.tags = [LogTag(key: key, value: "pay_old")]
        #expect(try await store.events(matching: query).map(\.message) == ["old pair reused"])
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

    // MARK: Write-failure recovery

    @Test func failedWritesRollBackSoLaterWritesSucceed() async throws {
        let (store, root, _, _) = try await makeStore()

        await store.injectNextWriteFailure(InjectedSaveFailure())
        await store.write([makeRecord("poisoned", date: date(1), scopes: [root.id])])
        #expect(await store.writeFailureCount == 1)

        await store.write([makeRecord("healthy", date: date(2), scopes: [root.id])])

        // The poisoned batch is gone, but the store says so durably: a
        // StoreWriteFailed marker records the gap's size and cause.
        let events = try await store.events(matching: LogQuery())
        #expect(events.map(\.message).contains("healthy"))
        #expect(!events.map(\.message).contains("poisoned"))
        let marker = try #require(events.first { $0.eventName == StoreWriteFailed.eventName })
        let decoded = try marker.decode(StoreWriteFailed.self)
        #expect(decoded.lostRecordCount == 1)
        #expect(decoded.reason.contains("InjectedSaveFailure"))
        #expect(await store.writeFailureCount == 1)
    }

    @Test func recoveryDropsStaleRowCachesButKeepsScopesWorking() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let scope = LogScope.root(named: "late")
        let key = LogTagKey("payment-id")

        // The failed batch stages a placeholder scope row and a tag row;
        // both roll back with it.
        await store.injectNextWriteFailure(InjectedSaveFailure())
        await store.write([
            LogRecord(
                date: date(1),
                event: Message(level: .info, "poisoned"),
                scopes: [scope.id],
                tags: [LogTag(key: key, value: "pay_1")],
            ),
        ])
        #expect(try await store.scope(for: scope.id) == nil)

        await store.defineScopes([scope])
        await store.write([
            LogRecord(
                date: date(2),
                event: Message(level: .info, "healthy"),
                scopes: [scope.id],
                tags: [LogTag(key: key, value: "pay_1")],
            ),
        ])

        #expect(try await store.scope(for: scope.id) == scope)
        var query = LogQuery()
        query.tags = [LogTag(key: key, value: "pay_1")]
        #expect(try await store.events(matching: query).map(\.message) == ["healthy"])
    }

    @Test func recoveryKeepsTheSessionIdentity() async throws {
        let session = LogSession.fixture()
        let store = try await PeriscopeStore.inMemory(session: session)
        let root = LogScope.root(named: "app")
        await store.defineScopes([root])

        await store.injectNextWriteFailure(InjectedSaveFailure())
        await store.write([makeRecord("poisoned", date: date(1), scopes: [root.id])])
        await store.write([makeRecord("healthy", date: date(2), scopes: [root.id])])

        let event = try #require(try await store.events(matching: LogQuery()).first)
        #expect(event.sessionID == session.id)
        #expect(try await store.sessions().count == 1)
    }

    @Test func failedScopeDefinitionsRecoverOnRetry() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let scope = LogScope.root(named: "app")

        await store.injectNextWriteFailure(InjectedSaveFailure())
        await store.defineScopes([scope])
        #expect(await store.writeFailureCount == 1)
        #expect(try await store.scope(for: scope.id) == nil)

        await store.defineScopes([scope])
        #expect(try await store.scope(for: scope.id) == scope)
        #expect(try await store.scopes().count == 1)
    }

    @Test func failedDeletionsRollBackInsteadOfLingering() async throws {
        let (store, root, _, _) = try await makeStore()
        await store.write([
            makeRecord("old", date: date(1), scopes: [root.id]),
            makeRecord("new", date: date(100), scopes: [root.id]),
        ])

        await store.injectNextWriteFailure(InjectedSaveFailure())
        await #expect(throws: InjectedSaveFailure.self) {
            try await store.pruneEvents(olderThan: date(50))
        }
        #expect(try await store.events(matching: LogQuery()).count == 2)

        // The staged deletions must not ride along with the next commit.
        await store.write([makeRecord("later", date: date(200), scopes: [root.id])])
        #expect(try await store.events(matching: LogQuery()).count == 3)

        let removed = try await store.pruneEvents(olderThan: date(50))
        #expect(removed == 1)
        #expect(try await store.events(matching: LogQuery()).map(\.message) == ["later", "new"])
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
