import Foundation
import PeriscopeCore
import Testing

struct AmbientEventTests {
    @Test func messageCombinesKindAndSortedFields() {
        let event = AmbientEvent(kind: .network, value: ["status": "unsatisfied"])
        #expect(event.message == "network: status=unsatisfied")
        #expect(event.level == .info)
    }

    @Test func messageOrdersFieldsDeterministically() {
        let event = AmbientEvent(
            kind: .network,
            value: ["status": "satisfied", "interfaces": "wifi"],
        )
        #expect(event.message == "network: interfaces=wifi, status=satisfied")
    }

    @Test func levelCanBeRaised() {
        let event = AmbientEvent(kind: .memory, value: ["pressure": "warning"], level: .warning)
        #expect(event.level == .warning)
    }

    @Test func appsCanDefineTheirOwnKinds() {
        let custom = AmbientKind("push-token")
        let event = AmbientEvent(kind: custom, value: ["state": "refreshed"])
        #expect(event.message == "push-token: state=refreshed")
    }

    @Test func roundTripsThroughCodable() throws {
        let event = AmbientEvent(
            kind: .thermalState,
            value: ["level": "serious", "throttled": true, "steps": 3, "factor": 1.5],
            level: .warning,
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AmbientEvent.self, from: data)
        #expect(decoded == event)
    }

    /// The value is a plain JSON object with bare scalars — not the
    /// case-keyed wrapper a synthesized enum coding would emit — so a
    /// stored payload reads as data anywhere JSON is spoken.
    @Test func valueEncodesAsAPlainJSONObject() throws {
        let event = AmbientEvent(
            kind: .accessibility,
            value: ["voiceover": false, "contrast": "high", "retries": 2],
        )
        let data = try JSONEncoder().encode(event)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let value = try #require(json["value"] as? [String: Any])
        #expect(value["voiceover"] as? Bool == false)
        #expect(value["contrast"] as? String == "high")
        #expect(value["retries"] as? Int == 2)
    }

    @Test func reportsLastingStateByDefault() {
        #expect(AmbientEvent(kind: .network, value: ["status": "satisfied"]).reporting == .state)
    }

    @Test func roundTripsMomentaryReporting() throws {
        let event = AmbientEvent(
            kind: .memory,
            value: ["pressure": "warning"],
            level: .warning,
            reporting: .occurrence,
        )
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(AmbientEvent.self, from: data) == event)
    }
}
