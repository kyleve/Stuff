import Foundation
import PeriscopeCore
import Testing

struct AmbientEventTests {
    @Test func messageCombinesKindAndValue() {
        let event = AmbientEvent(kind: .network, value: "unsatisfied")
        #expect(event.message == "network: unsatisfied")
        #expect(event.level == .info)
    }

    @Test func levelCanBeRaised() {
        let event = AmbientEvent(kind: .memory, value: "warning", level: .warning)
        #expect(event.level == .warning)
    }

    @Test func appsCanDefineTheirOwnKinds() {
        let custom = AmbientKind("push-token")
        let event = AmbientEvent(kind: custom, value: "refreshed")
        #expect(event.message == "push-token: refreshed")
    }

    @Test func roundTripsThroughCodable() throws {
        let event = AmbientEvent(kind: .thermalState, value: "serious", level: .warning)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AmbientEvent.self, from: data)
        #expect(decoded == event)
    }
}
