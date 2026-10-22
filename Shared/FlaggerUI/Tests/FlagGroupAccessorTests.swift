import Flagger
@testable import FlaggerUI
import Testing

@MainActor
struct FlagGroupAccessorTests {
    @Test
    func environmentStyleGroupAccessReadsAndWritesTypedValue() async throws {
        let model = try await makeFlaggerModel()

        #expect(model.ui.enabled == false)
        try await model.ui.set(true, for: \.enabled)
        #expect(model.ui.enabled == true)
    }

    @Test
    func throwingGroupReadIsAvailable() async throws {
        let model = try await makeFlaggerModel()

        #expect(try model.ui.value(for: \.launchStyle) == "standard")
    }
}
