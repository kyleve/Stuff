import Foundation
import PortholeCore
import Testing

struct PortholeObservationOwnershipTests {
    @Test func structuredAndInheritedCallsKeepNativeOwnership() async {
        let owner = PortholeObservationOwnerID(rawValue: UUID())
        await PortholeObservationOwnership.$current.withValue(owner) {
            let inherited = Task { PortholeObservationOwnership.current }
            #expect(await inherited.value == owner)
            #expect(PortholeObservationOwnership.current == owner)
        }
        #expect(PortholeObservationOwnership.current == nil)
    }
}
