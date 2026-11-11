@testable import Flagger
import Testing

struct FlagTests {
    @Test
    func definitionKeepsStableIdentityAndDefault() {
        let flag = Flag<Bool, LiveUpdating>(
            "test.flag",
            name: "Test Flag",
            detail: "Detail",
            default: true,
        )

        #expect(flag.id == FlagID(rawValue: "test.flag"))
        #expect(flag.name == "Test Flag")
        #expect(flag.detail == "Detail")
        #expect(flag.defaultValue)
    }
}
