import Foundation
import PeriscopeCore
import Testing

struct AmbientEventTests {
    @Test(arguments: AmbientLog.AppLifecycle.Phase.allCases)
    func lifecycleApprovesOnlyClosedPhases(phase: AmbientLog.AppLifecycle.Phase) throws {
        let event = AmbientLog.AppLifecycle(phase: .shared(.category, phase))
        #expect(event.classifiedFields == [.shareable(
            key: LogFieldKey("phase"),
            kind: .category,
            value: .string(phase.rawValue),
        )])
        #expect(event.message == "app-lifecycle: phase=\(phase.rawValue)")
        #expect(AmbientLog.AppLifecycle.eventName == "ambient.app-lifecycle")
        #expect(try JSONDecoder().decode(
            AmbientLog.AppLifecycle.self,
            from: JSONEncoder().encode(event),
        ).phase == phase)
    }

    @Test(arguments: AmbientLog.ThermalState.Condition.allCases)
    func thermalApprovesOnlyClosedConditions(condition: AmbientLog.ThermalState.Condition) {
        let event = AmbientLog.ThermalState(condition: .shared(.category, condition))
        #expect(event.classifiedFields == [.shareable(
            key: LogFieldKey("condition"),
            kind: .category,
            value: .string(condition.rawValue),
        )])
        #expect(event.message == "thermal-state: level=\(condition.rawValue)")
    }

    @Test(arguments: [false, true])
    func powerModeApprovesItsBoolean(enabled: Bool) {
        let event = AmbientLog.PowerMode(enabled: .shared(.boolean, enabled))
        #expect(event.classifiedFields == [.shareable(
            key: LogFieldKey("low_power"),
            kind: .boolean,
            value: .bool(enabled),
        )])
        #expect(event.message == "power-mode: low-power=\(enabled)")
    }

    @Test func memoryWarningRemainsAnOccurrence() {
        let event = AmbientLog.MemoryWarning()
        #expect(event.classifiedFields.isEmpty)
        #expect(event.level == .warning)
        #expect(event.reporting == .occurrence)
        #expect(AmbientLog.MemoryWarning.eventName == "ambient.memory-warning")
        #expect(AmbientSnapshot.folding(event, into: nil) == nil)
    }

    @Test(arguments: AmbientLog.Network.Status.allCases)
    func networkApprovesConnectivityButNotInterfaces(status: AmbientLog.Network.Status) throws {
        let event = AmbientLog.Network(
            status: .shared(.category, status),
            interfaces: .restricted(.technicalState, [.wifi]),
        )
        #expect(event.classifiedFields == [
            .shareable(
                key: LogFieldKey("status"),
                kind: .category,
                value: .string(status.rawValue),
            ),
            .restricted(key: LogFieldKey("interfaces"), kind: .technicalState),
        ])
        #expect(try JSONDecoder().decode(
            AmbientLog.Network.self,
            from: JSONEncoder().encode(event),
        ) == event)
    }

    @Test func customPayloadsNeverInheritBuiltinApproval() {
        let event = makeAmbientEvent(kind: .appLifecycle, value: ["phase": "private-user-data"])
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("kind"), kind: .technicalState),
            .restricted(key: LogFieldKey("value"), kind: .domainValue),
            .restricted(key: LogFieldKey("level"), kind: .technicalState),
            .restricted(key: LogFieldKey("reporting"), kind: .technicalState),
        ])
    }

    @Test func messageCombinesKindAndSortedFields() {
        let event = makeAmbientEvent(kind: .network, value: ["status": "unsatisfied"])
        #expect(event.message == "network: status=unsatisfied")
        #expect(event.level == .info)
    }

    @Test func messageOrdersFieldsDeterministically() {
        let event = makeAmbientEvent(
            kind: .network,
            value: ["status": "satisfied", "interfaces": "wifi"],
        )
        #expect(event.message == "network: interfaces=wifi, status=satisfied")
    }

    @Test func levelCanBeRaised() {
        let event = makeAmbientEvent(
            kind: .memory,
            value: ["pressure": "warning"],
            level: .warning,
        )
        #expect(event.level == .warning)
    }

    @Test func appsCanDefineTheirOwnKinds() {
        let custom = AmbientKind("push-token")
        let event = makeAmbientEvent(kind: custom, value: ["state": "refreshed"])
        #expect(event.message == "push-token: state=refreshed")
    }

    @Test func roundTripsThroughCodable() throws {
        let event = makeAmbientEvent(
            kind: .thermalState,
            value: ["level": "serious", "throttled": true, "steps": 3, "factor": 1.5],
            level: .warning,
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AmbientLog.Event.self, from: data)
        #expect(decoded == event)
    }

    /// The value is a plain JSON object with bare scalars — not the
    /// case-keyed wrapper a synthesized enum coding would emit — so a
    /// stored payload reads as data anywhere JSON is spoken.
    @Test func valueEncodesAsAPlainJSONObject() throws {
        let event = makeAmbientEvent(
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
        #expect(makeAmbientEvent(kind: .network, value: ["status": "satisfied"])
            .reporting == .state)
    }

    @Test func roundTripsMomentaryReporting() throws {
        let event = makeAmbientEvent(
            kind: .memory,
            value: ["pressure": "warning"],
            level: .warning,
            reporting: .occurrence,
        )
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(AmbientLog.Event.self, from: data) == event)
    }
}
