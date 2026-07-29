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

    @Test func reportsLastingStateByDefault() {
        #expect(AmbientEvent(kind: .network, value: "satisfied").reporting == .state)
    }

    @Test func roundTripsMomentaryReporting() throws {
        let event = AmbientEvent(
            kind: .memory,
            value: "warning",
            level: .warning,
            reporting: .occurrence,
        )
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(AmbientEvent.self, from: data) == event)
    }

    /// v1 rows predate `reporting` entirely; they must still decode (as
    /// state changes, which is what v1 sources reported) rather than throw.
    @Test func decodesVersionOnePayloadWithoutReporting() throws {
        let v1 = try JSONEncoder().encode(
            VersionOneAmbientEvent(kind: .network, value: "unsatisfied", level: .info),
        )
        let decoded = try JSONDecoder().decode(AmbientEvent.self, from: v1)
        #expect(decoded == AmbientEvent(kind: .network, value: "unsatisfied"))
        #expect(decoded.reporting == .state)
    }

    /// The one v1 exception: every v1 `.memory` event was a memory warning
    /// — an instant, not a condition — so it must not read back as a state
    /// the app was stuck in.
    @Test func versionOneMemoryEventsDecodeAsOccurrences() throws {
        let v1 = try JSONEncoder().encode(
            VersionOneAmbientEvent(kind: .memory, value: "warning", level: .warning),
        )
        let decoded = try JSONDecoder().decode(AmbientEvent.self, from: v1)
        #expect(decoded.reporting == .occurrence)
    }

    /// The payload shape v1 wrote: the same keys minus `reporting`. Encoded
    /// rather than hand-written JSON so it tracks `AmbientKind`/`LogLevel`
    /// coding instead of freezing a guess about it.
    private struct VersionOneAmbientEvent: Encodable {
        var kind: AmbientKind
        var value: String
        var level: LogLevel
    }
}
