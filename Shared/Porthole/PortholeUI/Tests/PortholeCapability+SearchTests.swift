import PortholeCore
@testable import PortholeUI
import Testing

struct PortholeCapabilitySearchTests {
    @Test(arguments: ["", "readValue", "Example", "Callback", "transport"])
    func searchesTheSameDescriptionAndUnsupportedReason(search: String) {
        let capability = PortholeCapability(
            id: .init(rawValue: "Example.readValue"),
            module: .init(rawValue: "Example"),
            name: "readValue",
            summary: "Read the transport value",
            parameters: [],
            result: .any,
            effect: .unknown,
            source: nil,
            ownership: .unisolated,
            availability: .unsupported("Callback parameters require a focused adapter"),
        )
        #expect(capability.matches(search: search))
        #expect(!capability.matches(search: "unrelated condition"))
    }
}
