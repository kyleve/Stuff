import Foundation
import PeriscopeCore
import Testing

struct StoredLogEventTests {
    private func makeStored(payload: Data) -> StoredLogEvent {
        let scope = LogScope.root(named: "photos")
        return StoredLogEvent(
            id: UUID(),
            date: Date(timeIntervalSinceReferenceDate: 100),
            sequence: 0,
            level: .notice,
            eventName: PhotoLogs.eventName,
            eventVersion: PhotoLogs.eventVersion,
            message: "photo p1",
            payload: payload,
            scopes: [scope.id],
            tags: [LogTag(key: LogTagKey("payment-id"), value: "pay_123")],
            spanID: nil,
            spanExitMode: nil,
            callSite: nil,
            externalID: nil,
            attachments: [],
            sessionID: UUID(),
            ambientSnapshotID: nil,
        )
    }

    @Test func decodeRecoversTheOriginalEvent() throws {
        let payload = try JSONEncoder().encode(PhotoLogs(photoID: "p1"))
        let stored = makeStored(payload: payload)

        let decoded = try stored.decode(PhotoLogs.self)
        #expect(decoded.photoID == "p1")
    }

    @Test func decodeThrowsWhenTheShapeNoLongerMatches() throws {
        let payload = try JSONEncoder().encode(Message(level: .info, "not a photo"))
        let stored = makeStored(payload: payload)

        #expect(throws: (any Error).self) {
            try stored.decode(PhotoLogs.self)
        }
    }

    @Test func primaryScopeIsTheFirstScope() {
        let stored = makeStored(payload: Data())
        #expect(stored.primaryScope == stored.scopes.first)
    }
}
