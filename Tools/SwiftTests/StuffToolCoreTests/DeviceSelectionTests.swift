import Foundation
import StuffToolCore
import Testing

struct DeviceSelectionTests {
    @Test func exactNameUDIDAndIdentifierFiltersSelectPhysicalDevices() throws {
        let data = try fixtureData("devicectl-devices", extension: "json")
        let selector = DeviceSelector()

        #expect(try selector.select(from: data, filter: "kai's iphone") == DeviceSelection(
            identifier: "DEVICE-A",
            name: "Kai's iPhone",
            connectionState: "disconnected",
        ))
        #expect(try selector.select(from: data, filter: "udid-b").identifier == "DEVICE-B")
        #expect(try selector.select(from: data, filter: "device-b").name == "Test iPad")
    }

    @Test func autoSelectionRequiresExactlyOnePhysicalIOSFamilyDevice() throws {
        let one = Data("""
        {"result":{"devices":[{
          "identifier":"ONLY",
          "properties":{
            "hardware":{"platform":"iOS","reality":"physical"},
            "state":{"name":"Phone"}
          }
        }]}}
        """.utf8)
        #expect(try DeviceSelector().select(from: one, filter: nil).identifier == "ONLY")

        let multiple = try fixtureData("devicectl-devices", extension: "json")
        do {
            _ = try DeviceSelector().select(from: multiple, filter: nil)
            Issue.record("expected ambiguity")
        } catch let failure as DeviceSelectionFailure {
            #expect(failure.description.contains("DEVICE-A"))
            #expect(failure.description.contains("DEVICE-B"))
            #expect(failure.description.contains("SIMULATOR") == false)
        }
    }

    @Test func connectionStateDoesNotHideAPairedPhone() throws {
        let data = try fixtureData("devicectl-devices", extension: "json")

        let selected = try DeviceSelector().select(from: data, filter: "DEVICE-A")

        #expect(selected.connectionState == "disconnected")
    }

    @Test func malformedAndMissingSelectionsAreObservable() {
        #expect(throws: DeviceSelectionFailure.self) {
            _ = try DeviceSelector().select(from: Data("{".utf8), filter: nil)
        }
        #expect(throws: DeviceSelectionFailure.self) {
            _ = try DeviceSelector().select(
                from: Data("{\"result\":{\"devices\":[]}}".utf8),
                filter: nil,
            )
        }
        #expect(throws: DeviceSelectionFailure.self) {
            _ = try DeviceSelector().select(
                from: fixtureData("devicectl-devices", extension: "json"),
                filter: "iPhone",
            )
        }
    }
}
