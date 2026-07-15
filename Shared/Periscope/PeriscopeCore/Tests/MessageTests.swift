import Foundation
import PeriscopeCore
import Testing

struct MessageTests {
    @Test func rendersItsStoredText() {
        let message = Message(level: .warning, "Falling back to cache")
        #expect(message.message == "Falling back to cache")
        #expect(message.level == .warning)
    }

    @Test func usesAStableEventName() {
        #expect(Message.eventName == "message")
    }

    @Test func roundTripsThroughCodable() throws {
        let message = Message(level: .error, "Request failed")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded == message)
    }
}
