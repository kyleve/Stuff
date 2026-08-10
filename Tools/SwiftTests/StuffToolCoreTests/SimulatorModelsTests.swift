import Foundation
import StuffToolCore
import Testing

struct SimulatorModelsTests {
    @Test func decodesDevicesAndSelectsTheFirstAmbiguousMatch() throws {
        let data = try fixtureData("simctl-devices", extension: "json")

        let list = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
        let matches = list.devices(
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            named: "iPhone 17",
        )

        #expect(matches.count == 2)
        #expect(SimulatorSelection.select(matches) == .selected(udid: "FIRST", ambiguousCount: 2))
        #expect(SimulatorSelection.select([]) == .missing)
    }
}
