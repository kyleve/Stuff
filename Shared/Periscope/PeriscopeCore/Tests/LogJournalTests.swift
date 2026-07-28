import Foundation
import JournalKit
@_spi(Testing) import PeriscopeCore
import Testing

struct LogJournalTests {
    private func makeDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("log-journal-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Decode every recovered payload this build understands.
    private func entries(in directory: URL) throws -> [LogJournalEntry] {
        try JournalRecovery.recover(directory: directory).payloads
            .compactMap { try LogJournalEntry.decoded(from: $0) }
    }

    @Test func opensWithTheSessionAsItsFirstEntry() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = LogSession.fixture()
        let journal = try LogJournal(directory: directory, session: session)
        journal.close()

        #expect(try entries(in: directory) == [.session(session)])
    }

    @Test func journalCapturesRecordsBeforeAnyDrain() throws {
        // The whole point: records reach disk synchronously at emit, even
        // when the async pipeline never runs — a gated sink stands in for
        // "the process died before draining".
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = GateSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [gate])
        let journal = try LogJournal(directory: directory, session: .fixture())
        system.install(journal: journal)

        let log = Log<AppLogs>(system: system)(for: "checkout")
        log.info("about to crash")
        log.error("crashed")

        let recovered = try entries(in: directory)
        let records = recovered.compactMap { entry -> LogJournalRecord? in
            guard case let .record(record) = entry else { return nil }
            return record
        }
        #expect(records.map(\.message) == ["about to crash", "crashed"])
        #expect(records.map(\.sequence) == records.map(\.sequence).sorted())

        // Scope definitions rode along, so the hierarchy is recoverable.
        let scopes = recovered.compactMap { entry -> LogScope? in
            guard case let .scope(scope) = entry else { return nil }
            return scope
        }
        #expect(scopes.contains { $0.name == "checkout" })
        gate.open()
    }

    @Test func spanPairsJournalInOrder() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [CapturingSink()])
        let journal = try LogJournal(directory: directory, session: .fixture())
        system.install(journal: journal)

        let log = Log<AppLogs>(system: system)
        log.begin(for: "checkout", lifetime: .indefinite)
        log.end(for: "checkout", exit: .success)

        let records = try entries(in: directory).compactMap { entry -> LogJournalRecord? in
            guard case let .record(record) = entry else { return nil }
            return record
        }
        #expect(records.map(\.eventName) == [SpanBegan.eventName, SpanEnded.eventName])
        #expect(records[0].sequence < records[1].sequence)
        #expect(records[0].spanID == records[1].spanID)
    }

    @Test func journaledRecordsCarryTheAmbientStateTheyWereStampedWith() throws {
        // Crash recovery must not lose the system context: a record whose
        // only copy is the journal should still say what the network was
        // doing when it was emitted.
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [CapturingSink()])
        let journal = try LogJournal(directory: directory, session: .fixture())
        system.install(journal: journal)

        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "unsatisfied") }
        Log<AppLogs>(system: system).error("failed while offline")

        let records = try entries(in: directory).compactMap { entry -> LogJournalRecord? in
            guard case let .record(record) = entry else { return nil }
            return record
        }
        let failure = try #require(records.first { $0.message == "failed while offline" })
        #expect(failure.ambient?[.network] == "unsatisfied")
    }

    @Test func journalWritesOnlyRedactedContent() throws {
        // The journal taps in *after* redaction — the highest-consequence
        // placement in the pipeline, since journal files outlive the
        // process. The raw segment bytes are the tripwire: the secret must
        // not appear anywhere on disk, and a suppressed record must not
        // appear at all.
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = Periscope(
            configuration: Periscope.Configuration(redact: { record in
                if record.message.contains("suppress-me") {
                    return nil
                }
                return LogRecord(
                    id: record.id,
                    date: record.date,
                    event: Message(level: record.level, "[redacted]"),
                    scopes: record.scopes,
                )
            }),
            sinks: [CapturingSink()],
        )
        let journal = try LogJournal(directory: directory, session: .fixture())
        system.install(journal: journal)

        let log = Log<AppLogs>(system: system)
        log.info("card number 4242-secret")
        log.info("suppress-me entirely")

        let records = try entries(in: directory).compactMap { entry -> LogJournalRecord? in
            guard case let .record(record) = entry else { return nil }
            return record
        }
        #expect(records.map(\.message) == ["[redacted]"])

        // The leak vectors are the journaled payload JSON, message, and
        // tags — check the decoded content (the envelope base64-wraps
        // nested payloads, so raw bytes can't be grepped for them).
        let payloadJSON = records.map { String(decoding: $0.payload, as: UTF8.self) }.joined()
        #expect(!payloadJSON.contains("4242-secret"))
        #expect(payloadJSON.contains("[redacted]"))

        // And nothing leaks in plaintext at the envelope level either.
        let segmentBytes = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { try Data(contentsOf: $0) }
            .reduce(Data(), +)
        let onDisk = String(decoding: segmentBytes, as: UTF8.self)
        #expect(!onDisk.contains("4242-secret"))
        #expect(!onDisk.contains("suppress-me"))
    }

    @Test func journalFailuresCountInsteadOfThrowingIntoTheEmitPath() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [CapturingSink()])
        let journal = try LogJournal(directory: directory, session: .fixture())
        system.install(journal: journal)
        journal.close() // every append now fails at the file layer

        let log = Log<AppLogs>(system: system)
        log.info("undeterred")

        // Two failed appends: the root scope definition (Log init) and the
        // record — both swallowed into telemetry, neither thrown.
        #expect(journal.appendFailureCount == 2)
    }

    @Test func onDiskStoresOpenAndInstallTheJournal() async throws {
        // No deferred cleanup: the ModelContainer outlives the test body,
        // and deleting the database under it logs CoreData I/O errors.
        // The directory lives in the simulator's ephemeral tmp.
        let root = makeDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = LogSession.fixture()
        let store = try await PeriscopeStore.onDisk(
            databaseURL: root.appendingPathComponent("Periscope.store"),
            session: session,
        )
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        system.add(sink: store)

        Log<AppLogs>(system: system).warning("journaled via the store")

        let directory = store.journalDirectory(forSession: session.id)
        let recovered = try entries(in: directory)
        #expect(recovered.first == .session(session))
        #expect(recovered.contains { entry in
            guard case let .record(record) = entry else { return false }
            return record.message == "journaled via the store"
        })
    }

    @Test func inMemoryStoresNeverJournal() async throws {
        let store = try await PeriscopeStore.inMemory(session: .fixture())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        system.add(sink: store)
        Log<AppLogs>(system: system).info("ephemeral")
        // No journal directory exists; nothing to recover, nothing crashed.
        #expect(store.journal == nil)
    }
}
