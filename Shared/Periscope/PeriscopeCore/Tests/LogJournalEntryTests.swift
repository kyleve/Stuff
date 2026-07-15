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
            event: PhotoLogs(photoID: "p1"),
            scopes: [scope.id],
            tags: [LogTag(key: key, value: .int(3))],
            attachments: [
                LogAttachment(name: "response", contentType: .json, data: Data([1, 2])),
            ],
            callSite: LogCallSite(function: "upload(_:)", fileID: "App/Uploader.swift"),
        )
        let journaled = try LogJournalRecord(record: record, sequence: 42)
        let entry = LogJournalEntry.record(journaled)
        let decoded = try LogJournalEntry.decoded(from: entry.encoded())

        guard case let .record(back) = try #require(decoded) else {
            Issue.record("expected a record entry")
            return
        }
        #expect(back == journaled)
        #expect(back.sequence == 42)
        #expect(back.eventName == PhotoLogs.eventName)
        #expect(back.scopes == [scope.id.rawValue])
        #expect(back.tags[key] == .int(3))
        #expect(back.callFunction == "upload(_:)")
        // The payload decodes back to the typed event.
        let event = try JSONDecoder().decode(PhotoLogs.self, from: back.payload)
        #expect(event.photoID == "p1")
    }

    @Test func oversizedAttachmentsAreOmittedWithAMarker() throws {
        let scope = LogScope.root(named: "app")
        let big = Data(repeating: 0xAB, count: LogJournalRecord.maximumInlineAttachmentBytes + 1)
        let record = LogRecord(
            date: Date(timeIntervalSinceReferenceDate: 1),
            event: Message(level: .info, "screenshotted"),
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

    @Test func unknownKindsDecodeAsNilNotErrors() throws {
        // A newer build's entry kind must be skippable, not fatal.
        let future = Data(#"{"v":9,"kind":"hologram","payload":""}"#.utf8)
        #expect(try LogJournalEntry.decoded(from: future) == nil)
    }

    @Test func malformedEntriesThrow() {
        #expect(throws: (any Error).self) {
            try LogJournalEntry.decoded(from: Data([0xFF, 0x00, 0x01]))
        }
    }
}
