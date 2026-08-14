import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

struct LogJournalEntryTests {
    @Test func sessionEntriesRoundTrip() throws {
        let entry = LogJournalEntry.session(.fixture())
        let decoded = try LogJournalEntry.decoded(from: entry.encoded())
        #expect(decoded == entry)
    }

    @Test func scopeEntriesRoundTrip() throws {
        let scope = LogScope.root(named: "app").child(named: "photos")
        let entry = LogJournalEntry.scope(scope)
        let decoded = try LogJournalEntry.decoded(from: entry.encoded())
        #expect(decoded == entry)
    }

    @Test func recordEntriesRoundTripEveryField() throws {
        let key = LogTagKey("payment-id")
        let scope = LogScope.root(named: "app")
        let record = LogRecord(
            date: Date(timeIntervalSinceReferenceDate: 123),
            event: makePhotoEvent("p1"),
            scopes: [scope.id],
            tags: [LogTag(key: key, value: .int(3))],
            attachments: [
                LogAttachment(name: "response", contentType: .json, data: Data([1, 2])),
            ],
            callSite: LogCallSite(function: "upload(_:)", fileID: "App/Uploader.swift"),
        )
        var journaled = try LogJournalRecord(record: record, sequence: 42)
        journaled.ambient = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        let entry = LogJournalEntry.record(journaled)
        let decoded = try LogJournalEntry.decoded(from: entry.encoded())

        guard case let .record(back) = try #require(decoded) else {
            Issue.record("expected a record entry")
            return
        }
        #expect(back == journaled)
        #expect(back.sequence == 42)
        #expect(back.ambient?[.network] == ["status": "satisfied"])
        #expect(back.eventName == PhotoLogs.Event.eventName)
        #expect(back.scopes == [scope.id.rawValue])
        #expect(back.tags[key] == .int(3))
        #expect(back.callFunction == "upload(_:)")
        // The payload decodes back to the typed event.
        let event = try JSONDecoder().decode(PhotoLogs.Event.self, from: back.payload)
        #expect(event.photoID == "p1")
    }

    /// The store persists a began's relaunch policy as a column, and the crash
    /// path has to be able to fill it — so the journal record carries the policy
    /// out of the event rather than leaving ingest to decode the payload.
    @Test func spanBegansCarryTheirRelaunchPolicy() throws {
        let record = LogRecord(
            date: Date(timeIntervalSinceReferenceDate: 5),
            event: makeSpanBegan(
                spanID: SpanID(),
                name: "long-download",
                lifetime: .indefinite,
                relaunchPolicy: .survivesRelaunch,
            ),
            scopes: [],
        )
        let journaled = try LogJournalRecord(record: record, sequence: 1)
        #expect(journaled.spanRelaunchPolicy == SpanRelaunchPolicy.survivesRelaunch.rawValue)

        let decoded = try LogJournalEntry.decoded(from: LogJournalEntry.record(journaled).encoded())
        #expect(decoded == .record(journaled))
    }

    /// Only a began has a policy — an end (or any other event) must not invent
    /// one, or the store's column would claim every row wanted to survive.
    @Test func nonBeganRecordsCarryNoRelaunchPolicy() throws {
        let record = LogRecord(
            date: Date(timeIntervalSinceReferenceDate: 6),
            event: makeSpanEnded(
                spanID: SpanID(),
                name: "long-download",
                duration: .seconds(1),
                exit: .success,
            ),
            scopes: [],
        )
        #expect(try LogJournalRecord(record: record, sequence: 1).spanRelaunchPolicy == nil)
    }

    @Test func oversizedAttachmentsAreOmittedWithAMarker() throws {
        let scope = LogScope.root(named: "app")
        let big = Data(repeating: 0xAB, count: LogJournalRecord.maximumInlineAttachmentBytes + 1)
        let record = LogRecord(
            date: Date(timeIntervalSinceReferenceDate: 1),
            event: makeMessage("screenshotted"),
            scopes: [scope.id],
            attachments: [
                LogAttachment(name: "small", contentType: .json, data: Data([1])),
                LogAttachment(name: "screenshot", contentType: .png, data: big),
            ],
        )
        let journaled = try LogJournalRecord(record: record, sequence: 1)

        #expect(journaled.attachments == [
            .inline(LogAttachment(name: "small", contentType: .json, data: Data([1]))),
            .omitted(name: "screenshot", contentType: .png, byteCount: big.count),
        ])
        // And the omission survives the wire format.
        let decoded = try LogJournalEntry.decoded(from: LogJournalEntry.record(journaled).encoded())
        #expect(decoded == .record(journaled))
    }

    @Test func envelopesNestPayloadsAsJSONObjectsNotBase64() throws {
        // The wire format pins the single-pass encoding: a base64 string
        // payload would mean re-encoded bytes and ~33% inflation.
        let entry = LogJournalEntry.session(.fixture())
        let object = try #require(
            try JSONSerialization.jsonObject(with: entry.encoded()) as? [String: Any],
        )
        #expect(object["v"] as? Int == 1)
        #expect(object["kind"] as? String == "session")
        #expect(object["payload"] is [String: Any])
    }

    @Test func unknownKindsDecodeAsNilNotErrors() throws {
        // A newer build's entry kind must be skippable, not fatal.
        let future = Data(#"{"v":9,"kind":"hologram","payload":""}"#.utf8)
        #expect(try LogJournalEntry.decoded(from: future) == nil)
    }

    /// A journal is written before an upgrade and ingested after one, so an
    /// entry from a build that predates ambient state — no `ambient` key at
    /// all — must still decode rather than throw the whole journal away.
    @Test func entriesWithoutAmbientStateStillDecode() throws {
        let record = LogRecord(
            date: Date(timeIntervalSinceReferenceDate: 7),
            event: makeMessage("from an older build"),
            scopes: [],
        )
        let journaled = try LogJournalRecord(record: record, sequence: 1)
        let encoded = try LogJournalEntry.record(journaled).encoded()

        let envelope = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any],
        )
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(payload["ambient"] == nil)
        #expect(try LogJournalEntry.decoded(from: encoded) == .record(journaled))
    }

    @Test func malformedEntriesThrow() {
        #expect(throws: (any Error).self) {
            try LogJournalEntry.decoded(from: Data([0xFF, 0x00, 0x01]))
        }
    }
}
