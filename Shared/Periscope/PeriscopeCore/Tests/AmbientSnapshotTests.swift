import Foundation
import PeriscopeCore
import Testing

struct AmbientSnapshotTests {
    @Test func firstStateEventStartsASnapshot() {
        let snapshot = AmbientSnapshot.folding(
            AmbientEvent(kind: .network, value: "satisfied"),
            into: nil,
        )
        #expect(snapshot?[.network] == "satisfied")
    }

    /// A snapshot that knows nothing would claim to describe the system
    /// while carrying no values — `nil` says "not observed yet" honestly.
    @Test func momentaryEventCannotCreateAnEmptySnapshot() {
        let snapshot = AmbientSnapshot.folding(
            AmbientEvent(kind: .memory, value: "warning", reporting: .occurrence),
            into: nil,
        )
        #expect(snapshot == nil)
    }

    @Test func changedValueTakesANewIdentity() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: "satisfied"])
        let second = first.applying(AmbientEvent(kind: .network, value: "unsatisfied"))
        #expect(second[.network] == "unsatisfied")
        #expect(second.id != first.id)
    }

    @Test func newKindJoinsTheExistingValues() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: "satisfied"])
        let second = first.applying(AmbientEvent(kind: .thermalState, value: "fair"))
        #expect(second[.network] == "satisfied")
        #expect(second[.thermalState] == "fair")
    }

    /// The dedupe contract: re-reporting the current value must not mint a
    /// new identity, or every repeat would persist another row.
    @Test func unchangedValueKeepsTheSameIdentity() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: "satisfied"])
        #expect(first.applying(AmbientEvent(kind: .network, value: "satisfied")) == first)
    }

    @Test func momentaryEventLeavesAnExistingSnapshotAlone() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: "satisfied"])
        let second = first.applying(
            AmbientEvent(kind: .memory, value: "warning", reporting: .occurrence),
        )
        #expect(second == first)
        #expect(second[.memory] == nil)
    }

    @Test func roundTripsThroughCodable() throws {
        let snapshot = AmbientSnapshot(
            id: UUID(),
            values: [.network: "satisfied", .thermalState: "nominal"],
        )
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(AmbientSnapshot.self, from: data) == snapshot)
    }

    /// Kinds encode as JSON object keys (via `CodingKeyRepresentable`), not
    /// the flat alternating array an unkeyed dictionary would produce — the
    /// stored blob stays readable by anything that isn't this Swift type.
    @Test func valuesEncodeAsAnObjectKeyedByKind() throws {
        let snapshot = AmbientSnapshot(id: UUID(), values: [.network: "satisfied"])
        let data = try JSONEncoder().encode(snapshot)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        #expect(json["values"] as? [String: String] == ["network": "satisfied"])
    }
}
