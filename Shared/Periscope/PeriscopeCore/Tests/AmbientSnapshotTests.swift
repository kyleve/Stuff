import Foundation
import PeriscopeCore
import Testing

struct AmbientSnapshotTests {
    @Test func firstStateEventStartsASnapshot() {
        let snapshot = AmbientSnapshot.folding(
            AmbientEvent(kind: .network, value: ["status": "satisfied"]),
            into: nil,
        )
        #expect(snapshot?[.network] == ["status": "satisfied"])
    }

    /// A snapshot that knows nothing would claim to describe the system
    /// while carrying no values — `nil` says "not observed yet" honestly.
    @Test func momentaryEventCannotCreateAnEmptySnapshot() {
        let snapshot = AmbientSnapshot.folding(
            AmbientEvent(kind: .memory, value: ["pressure": "warning"], reporting: .occurrence),
            into: nil,
        )
        #expect(snapshot == nil)
    }

    @Test func changedValueTakesANewIdentity() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        let second = first.applying(
            AmbientEvent(kind: .network, value: ["status": "unsatisfied"]),
        )
        #expect(second[.network] == ["status": "unsatisfied"])
        #expect(second.id != first.id)
    }

    @Test func newKindJoinsTheExistingValues() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        let second = first.applying(AmbientEvent(kind: .thermalState, value: ["level": "fair"]))
        #expect(second[.network] == ["status": "satisfied"])
        #expect(second[.thermalState] == ["level": "fair"])
    }

    /// The dedupe contract: re-reporting the current value must not mint a
    /// new identity, or every repeat would persist another row.
    @Test func unchangedValueKeepsTheSameIdentity() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        #expect(
            first.applying(AmbientEvent(kind: .network, value: ["status": "satisfied"])) == first,
        )
    }

    @Test func momentaryEventLeavesAnExistingSnapshotAlone() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        let second = first.applying(
            AmbientEvent(kind: .memory, value: ["pressure": "warning"], reporting: .occurrence),
        )
        #expect(second == first)
        #expect(second[.memory] == nil)
    }

    @Test func removingAKindDropsItUnderANewIdentity() {
        let first = AmbientSnapshot(
            id: UUID(),
            values: [.network: ["status": "satisfied"], .thermalState: ["level": "fair"]],
        )
        let second = first.removing(.network)
        #expect(second?[.network] == nil)
        #expect(second?[.thermalState] == ["level": "fair"])
        #expect(second?.id != first.id)
    }

    @Test func removingAnAbsentKindKeepsTheSameIdentity() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        #expect(first.removing(.thermalState) == first)
    }

    /// Removing the last kind must not leave an empty snapshot behind — an
    /// empty snapshot is not a state, it's the absence of one.
    @Test func removingTheOnlyKindDissolvesTheSnapshot() {
        let first = AmbientSnapshot(id: UUID(), values: [.network: ["status": "satisfied"]])
        #expect(first.removing(.network) == nil)
    }

    @Test func roundTripsThroughCodable() throws {
        let snapshot = AmbientSnapshot(
            id: UUID(),
            values: [
                .network: ["status": "satisfied", "expensive": false],
                .thermalState: ["level": "nominal"],
            ],
        )
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(AmbientSnapshot.self, from: data) == snapshot)
    }

    /// Kinds encode as JSON object keys (via `CodingKeyRepresentable`), and
    /// each value as a plain JSON object of bare scalars — not the flat
    /// alternating array an unkeyed dictionary would produce, and not a
    /// case-keyed enum wrapper — so the stored blob stays readable by
    /// anything that isn't this Swift type.
    @Test func valuesEncodeAsAnObjectKeyedByKind() throws {
        let snapshot = AmbientSnapshot(
            id: UUID(),
            values: [.network: ["status": "satisfied", "expensive": false]],
        )
        let data = try JSONEncoder().encode(snapshot)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let values = try #require(json["values"] as? [String: [String: Any]])
        #expect(values["network"]?["status"] as? String == "satisfied")
        #expect(values["network"]?["expensive"] as? Bool == false)
    }
}
