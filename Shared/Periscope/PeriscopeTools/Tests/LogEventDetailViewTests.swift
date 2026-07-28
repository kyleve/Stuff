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
        let ended = SpanEnded(
            spanID: SpanID(),
            name: "checkout",
            duration: nil,
            exit: .failure("card declined"),
        )
        let event = try stored(eventName: "span-ended", payload: JSONEncoder().encode(ended))

        #expect(event.exitReason == "card declined")
    }

    @Test func exitReasonIsNilWithoutAReason() throws {
        let ended = SpanEnded(spanID: SpanID(), name: "checkout", duration: nil, exit: .success)
        let event = try stored(eventName: "span-ended", payload: JSONEncoder().encode(ended))

        #expect(event.exitReason == nil)
    }

    @Test func exitReasonIsNilWhenThePayloadDoesNotDecode() {
        #expect(stored(payload: Data()).exitReason == nil)
        #expect(stored(payload: Data([0xFF, 0x00])).exitReason == nil)
    }

    @Test func prettyPayloadIndentsAndSortsKeys() throws {
        let payload = try JSONEncoder().encode(["zebra": 1, "apple": 2])
        let pretty = try #require(stored(payload: payload).prettyPayload)

        #expect(pretty.contains("\n"))
        let apple = try #require(pretty.range(of: "\"apple\""))
        let zebra = try #require(pretty.range(of: "\"zebra\""))
        #expect(apple.lowerBound < zebra.lowerBound)
    }

    @Test func prettyPayloadIsNilForEmptyOrGarbagePayloads() {
        #expect(stored(payload: Data()).prettyPayload == nil)
        #expect(stored(payload: Data([0xFF, 0x00])).prettyPayload == nil)
    }
}
