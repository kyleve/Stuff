import Foundation
import JournalKit
@_spi(Testing) import PeriscopeCore
import Testing

struct PeriscopeStoreJournalIngestTests {
    /// A root directory standing in for the app's storage across
    /// "launches". Lives in the simulator's ephemeral tmp; not deleted in
    /// the test body because ModelContainers outlive it.
    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ingest-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func databaseURL(in root: URL) -> URL {
        root.appendingPathComponent("Periscope.store")
    }

    /// Simulate a crashed launch: journal a session, scopes, and records
    /// into the directory a store at `databaseURL` will look in — then
    /// "crash" (close without any pipeline delivery).
    private func writeCrashedJournal(
        root: URL,
        session: LogSession,
        scopes: [LogScope],
        records: [LogRecord],
    ) throws {
        let journalDirectory = root
            .appendingPathComponent("Periscope-Journals", isDirectory: true)
            .appendingPathComponent(session.id.uuidString, isDirectory: true)
        let journal = try LogJournal(directory: journalDirectory, session: session)
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        system.install(journal: journal)
        for scope in scopes {
            system.defineScope(scope)
        }
        for record in records {
            system.record(record)
        }
        journal.close()
    }

    @Test func crashedSessionsRecoverIntoTheStore() async throws {
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app").child(named: "checkout")
        let key = LogTagKey("payment-id")
        try writeCrashedJournal(
            root: root,
            session: crashed,
            scopes: [LogScope.root(named: "app"), scope],
            records: [
                LogRecord(
                    date: date(1),
                    event: Message(level: .error, "about to die"),
                    scopes: [scope.id],
                    tags: [LogTag(key: key, value: "pay_1")],
                    callSite: LogCallSite(function: "buy()", fileID: "App/Checkout.swift"),
                ),
            ],
        )

        // The "next launch": the store ingests before its session starts.
        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )

        let events = try await store.events(matching: LogQuery())
        let recovered = try #require(events.first { $0.message == "about to die" })
        #expect(recovered.sessionID == crashed.id)
        #expect(recovered.level == .error)
        #expect(recovered.tags == [LogTag(key: key, value: "pay_1")])
        #expect(recovered.callSite?.function == "buy()")
        #expect(recovered.scopes == [scope.id])
        // The hierarchy came along.
        #expect(try await store.scope(for: scope.id) == scope)
        // The recovery is marked in the story, on the crashed session.
        let marker = try #require(events.first { $0.message.contains("crash journal") })
        #expect(marker.sessionID == crashed.id)
        #expect(marker.level == .notice)
        // And both launches' sessions exist.
        #expect(try await store.sessions().count == 2)
        // The crashed session's journal is gone once ingested (the new
        // launch's own journal directory remains, as it should).
        let crashedJournal = store.journalDirectory(forSession: crashed.id)
        #expect(!FileManager.default.fileExists(atPath: crashedJournal.path))
    }

    /// The full crash path for ambient state: stamped at emit, journaled,
    /// recovered, and given its row at ingest — so the events that only
    /// exist because of a crash still say what the system was doing.
    @Test func recoveredEventsKeepTheirAmbientState() async throws {
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app")
        try writeCrashedJournal(
            root: root,
            session: crashed,
            scopes: [scope],
            records: [
                LogRecord(
                    date: date(1),
                    event: AmbientEvent(kind: .network, value: "unsatisfied"),
                    scopes: [scope.id],
                ),
                LogRecord(
                    date: date(2),
                    event: Message(level: .error, "died while offline"),
                    scopes: [scope.id],
                ),
            ],
        )

        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )

        let events = try await store.events(matching: LogQuery())
        let recovered = try #require(events.first { $0.message == "died while offline" })
        let snapshotID = try #require(recovered.ambientSnapshotID)
        let snapshot = try await store.ambientSnapshot(for: snapshotID)
        #expect(snapshot?[.network] == "unsatisfied")
    }

    @Test func alreadyDeliveredRecordsAreNotDuplicated() async throws {
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app")

        // First launch: one record made it through the pipeline to the
        // store before the crash; a second only reached the journal.
        let firstStore = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: crashed,
        )
        let delivered = LogRecord(
            date: date(1),
            event: Message(level: .info, "delivered"),
            scopes: [scope.id],
        )
        await firstStore.defineScopes([scope])
        await firstStore.write([delivered])
        let journal = try #require(firstStore.journal)
        journal.append(delivered, sequence: 1)
        journal.append(
            LogRecord(
                date: date(2),
                event: Message(level: .info, "journal only"),
                scopes: [scope.id],
            ),
            sequence: 2,
        )
        journal.close()

        // Second launch, same database: dedupe by event ID.
        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )
        let events = try await store.events(matching: LogQuery())
        #expect(events.count(where: { $0.message == "delivered" }) == 1)
        #expect(events.count(where: { $0.message == "journal only" }) == 1)
    }

    @Test func recoveredSpanBegansJoinTheOrphanSweep() async throws {
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app")
        let began = SpanBegan(
            spanID: SpanID(),
            name: "checkout",
            lifetime: .indefinite,
            relaunchPolicy: .endsWithProcess,
        )
        // No floors are set on the crashed system, so the raw SpanBegan
        // record passes straight through the normal record path.
        let record = LogRecord(date: date(1), event: began, scopes: [scope.id])
        try writeCrashedJournal(root: root, session: crashed, scopes: [scope], records: [record])

        // The next launch ingests the began, then the session start's
        // orphan sweep closes the flow the crash abandoned.
        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )
        let pair = try await store.events(inSpan: began.spanID)
        #expect(pair.count == 2)
        let ended = try #require(pair.first { $0.eventName == SpanEnded.eventName })
        #expect(try ended.decode(SpanEnded.self).exit == .orphaned)
    }

    /// A span that asked to survive a relaunch must survive one it reached
    /// through the crash journal too: the recovered row carries the policy, so
    /// the sweep that runs right after ingest leaves it open.
    @Test func recoveredSpanBegansKeepTheirRelaunchPolicy() async throws {
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app")
        let began = SpanBegan(
            spanID: SpanID(),
            name: "long-download",
            lifetime: .indefinite,
            relaunchPolicy: .survivesRelaunch,
        )
        let record = LogRecord(date: date(1), event: began, scopes: [scope.id])
        try writeCrashedJournal(root: root, session: crashed, scopes: [scope], records: [record])

        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )

        let events = try await store.events(inSpan: began.spanID)
        #expect(events.map(\.eventName) == [SpanBegan.eventName])
    }

    @Test func tornJournalsEscalateTheRecoveryMarker() async throws {
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app")
        try writeCrashedJournal(
            root: root,
            session: crashed,
            scopes: [scope],
            records: [
                LogRecord(
                    date: date(1),
                    event: Message(level: .info, "intact"),
                    scopes: [scope.id],
                ),
                LogRecord(date: date(2), event: Message(level: .info, "torn"), scopes: [scope.id]),
            ],
        )
        // Tear the final entry, as a crash mid-append would.
        let journalDirectory = root
            .appendingPathComponent("Periscope-Journals", isDirectory: true)
            .appendingPathComponent(crashed.id.uuidString, isDirectory: true)
        let segment = try FileManager.default
            .contentsOfDirectory(at: journalDirectory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "journalsegment" }
        let segmentURL = try #require(segment)
        let bytes = try Data(contentsOf: segmentURL)
        try bytes.prefix(bytes.count - 5).write(to: segmentURL)

        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )
        let events = try await store.events(matching: LogQuery())
        #expect(events.contains { $0.message == "intact" })
        #expect(!events.contains { $0.message == "torn" })
        let marker = try #require(events.first { $0.message.contains("crash journal") })
        #expect(marker.level == .warning)
        #expect(marker.message.contains("torn entry"))
    }

    @Test func rotatedJournalsMarkTheirDroppedEntries() async throws {
        // A journal that rotated away old segments still attributes itself
        // (the session entry heads every segment) and its marker admits
        // the loss.
        let root = try makeRoot()
        let crashed = LogSession.fixture(startedAt: date(0))
        let scope = LogScope.root(named: "app")
        let journalDirectory = root
            .appendingPathComponent("Periscope-Journals", isDirectory: true)
            .appendingPathComponent(crashed.id.uuidString, isDirectory: true)
        let journal = try Journal(
            directory: journalDirectory,
            configuration: Journal.Configuration(
                maximumByteCount: 4096,
                segmentHeader: LogJournalEntry.session(crashed).encoded(),
            ),
        )
        try journal.append(LogJournalEntry.scope(scope).encoded(), sync: .processDeath)
        for index in 0 ..< 40 {
            let record = LogRecord(
                date: date(TimeInterval(index)),
                event: Message(level: .info, "storm-\(index)"),
                scopes: [scope.id],
            )
            try journal.append(
                LogJournalEntry.record(LogJournalRecord(record: record, sequence: index)).encoded(),
                sync: .processDeath,
            )
        }
        journal.close()

        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(startedAt: date(100)),
        )
        let events = try await store.events(matching: LogQuery())
        // The newest records survived; the oldest rotated away.
        #expect(events.contains { $0.message == "storm-39" })
        #expect(!events.contains { $0.message == "storm-0" })
        let marker = try #require(events.first { $0.message.contains("crash journal") })
        #expect(marker.level == .warning)
        #expect(marker.message.contains("older entries were dropped"))
        #expect(marker.sessionID == crashed.id)
    }

    @Test func journalsWithoutASessionEntryAreDiscarded() async throws {
        let root = try makeRoot()
        // A torn first write: entries exist, none of them the session.
        let orphanDirectory = root
            .appendingPathComponent("Periscope-Journals", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let raw = try Journal(
            directory: orphanDirectory,
            configuration: Journal.Configuration(maximumByteCount: 1_000_000),
        )
        try raw.append(
            LogJournalEntry.scope(LogScope.root(named: "app")).encoded(),
            sync: .processDeath,
        )
        raw.close()

        let store = try await PeriscopeStore.onDisk(
            databaseURL: databaseURL(in: root),
            session: .fixture(),
        )
        #expect(try await store.events(matching: LogQuery()).isEmpty)
        let journals = root.appendingPathComponent("Periscope-Journals")
        // The unattributable journal is gone, not retried forever.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: journals.path)
        #expect(!remaining.contains(orphanDirectory.lastPathComponent))
    }
}
