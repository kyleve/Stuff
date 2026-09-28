import Foundation
import PeriscopeCore
@testable import PeriscopeTools
import Testing

struct LogEventDetailViewTests {
    private func stored(
        eventName: String = "message",
        payload: Data = Data(),
    ) -> StoredLogEvent {
        StoredLogEvent(
            id: UUID(),
            date: date(1),
            sequence: 0,
            level: .info,
            eventName: eventName,
            eventVersion: 1,
            message: "hello",
            payload: payload,
            scopes: [LogScope.root(named: "app").id],
            tags: [],
            spanID: nil,
            spanExitMode: nil,
            callSite: nil,
            externalID: nil,
            attachments: [],
            sessionID: UUID(),
            ambientSnapshotID: nil,
        )
    }

    @Test func exitReasonDecodesFromThePayload() throws {
        let ended = classifiedSpanEnded(
            spanID: SpanID(),
            name: "checkout",
            duration: nil,
            exit: .failure("card declined"),
        )
        let event = try stored(eventName: "span-ended", payload: JSONEncoder().encode(ended))

        #expect(event.exitReason == "card declined")
    }

    @Test func exitReasonIsNilWithoutAReason() throws {
        let ended = classifiedSpanEnded(
            spanID: SpanID(),
            name: "checkout",
            duration: nil,
            exit: .success,
        )
        let event = try stored(eventName: "span-ended", payload: JSONEncoder().encode(ended))

        #expect(event.exitReason == nil)
    }

    @Test func exitReasonIsNilWhenThePayloadDoesNotDecode() {
        #expect(stored(payload: Data()).exitReason == nil)
        #expect(stored(payload: Data([0xFF, 0x00])).exitReason == nil)
    }

    @Test func payloadPresentationIndentsAndSortsKeys() throws {
        let payload = try JSONEncoder().encode(["zebra": 1, "apple": 2])
        guard case let .json(pretty) = stored(payload: payload).payloadPresentation else {
            Issue.record("Expected a JSON presentation")
            return
        }

        #expect(pretty.contains("\n"))
        let apple = try #require(pretty.range(of: "\"apple\""))
        let zebra = try #require(pretty.range(of: "\"zebra\""))
        #expect(apple.lowerBound < zebra.lowerBound)
    }

    @Test func payloadPresentationIsNilOnlyWhenNoPayloadWasRecorded() {
        #expect(stored(payload: Data()).payloadPresentation == nil)
    }

    /// Garbage bytes mean on-disk corruption — the detail view must say a
    /// payload existed and didn't survive, not hide the section as if none
    /// was recorded.
    @Test func payloadPresentationMarksUnparseableBytesAsUnreadable() {
        let presentation = stored(payload: Data([0xFF, 0x00])).payloadPresentation
        #expect(presentation == .unreadable(byteCount: 2))
    }
}
