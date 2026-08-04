@testable import Flagger
import Foundation
import Testing

struct FlagOverrideTests {
    @Test
    func storesItsPersistentKeyAndJSONData() {
        let data = Data("true".utf8)
        let override = FlagOverride(key: "module.flag", value: data)

        #expect(override.key == "module.flag")
        #expect(override.value == data)
    }
}
