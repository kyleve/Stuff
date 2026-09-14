import Foundation
@testable import PortholeRuntime
import Testing

struct PortholeObjectReferencesTests {
    @Test func findsNestedArgumentsAndRejectsAnotherGeneration() throws {
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let reference = PortholeObjectReference(id: UUID(), scope: scope, typeName: "Example")
        let invocation = try PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "test"),
            receiver: reference,
            arguments: .object(["items": .array([.object(["$reference": .encoding(reference)])])]),
        )
        #expect(try PortholeObjectReferences.inArguments(of: invocation) == [reference, reference])
        let changed = PortholeInvocation(
            id: UUID(),
            scope: .init(id: scope.id, generation: UUID()),
            capabilityID: invocation.capabilityID,
            receiver: reference,
            arguments: .null,
        )
        #expect(throws: PortholeError.staleScope) {
            try PortholeObjectReferences.inArguments(of: changed)
        }
    }
}
