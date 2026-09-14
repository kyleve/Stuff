import Foundation
import PortholeCore
import Testing

struct PortholeExecutionOwnershipTests {
    @Test(arguments: [
        PortholeExecutionOwnership.unisolated,
        .mainActor,
        .actorInstance(typeName: "Engine"),
        .adapter,
    ])
    func preservesOwnershipAcrossTheWire(_ ownership: PortholeExecutionOwnership) throws {
        let data = try JSONEncoder().encode(ownership)
        #expect(try JSONDecoder().decode(PortholeExecutionOwnership.self, from: data) == ownership)
    }
}
