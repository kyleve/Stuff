@testable import Flagger
import Testing

struct FlagIDTests {
    @Test
    func descriptionUsesTheStableRawValue() {
        let id = FlagID(rawValue: "module.flag")

        #expect(id.description == "module.flag")
    }
}
