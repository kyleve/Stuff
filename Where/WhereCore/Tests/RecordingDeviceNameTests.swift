import Testing
@testable import WhereCore

struct RecordingDeviceNameTests {
    @Test(arguments: [
        ("iPhone16,1", "iPhone 15 Pro"),
        ("iPad13,18", "iPad (10th generation)"),
        ("iPad13,19", "iPad (10th generation)"),
        ("FuturePhone99,1", "FuturePhone99,1"),
    ])
    func resolvesTheOriginalDevicesModel(identifier: String, name: String) {
        #expect(RecordingDeviceName.modelLabel(for: identifier) == name)
    }

    @Test(arguments: [nil, "", "  ", " iPhone 15 Pro "])
    func acceptingOrClearingTheNameUsesTheModel(draft: String?) {
        #expect(RecordingDeviceName.normalizedNickname(draft, fallback: "iPhone 15 Pro") == nil)
        #expect(RecordingDeviceName
            .displayName(nickname: draft, fallback: "iPhone 15 Pro") == "iPhone 15 Pro")
    }

    @Test func customNameIsTrimmedForDisplayAndStorage() {
        #expect(RecordingDeviceName.normalizedNickname(
            "  Travel Phone  ",
            fallback: "iPhone 15 Pro",
        ) == "Travel Phone")
    }
}
