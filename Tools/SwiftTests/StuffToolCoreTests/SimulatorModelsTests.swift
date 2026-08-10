import Foundation
import StuffToolCore
import Testing

struct SimulatorModelsTests {
    @Test func decodesDevicesAndSelectsTheFirstAmbiguousMatch() throws {
        let data = Data("""
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
              {"name":"iPhone 17","udid":"FIRST","state":"Shutdown"},
              {"name":"iPhone 17","udid":"SECOND","state":"Booted"}
            ]
          }
        }
        """.utf8)

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
