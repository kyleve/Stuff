import Foundation
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingDeviceSetupModelTests {
    @Test func replacementRequiresAnIndependentRemovalChoiceAndChangingDeviceClearsIt() {
        let model = OnboardingDeviceSetupModel()
        let first = RecordingDeviceID(rawValue: UUID())
        let second = RecordingDeviceID(rawValue: UUID())
        #expect(model.mode == .additional)
        model.replacementDeviceID = first
        #expect(model.deviceToRemove == nil)
        model.removesOldDevice = true
        #expect(model.deviceToRemove == first)
        model.isConfirmingRemoval = true
        model.replacementDeviceID = second
        #expect(model.mode == .replacement(second, removeOldDevice: false))
        #expect(!model.isConfirmingRemoval)
        model.removesOldDevice = true
        model.replacementDeviceID = nil
        #expect(model.mode == .additional)
        #expect(model.deviceToRemove == nil)
    }
}
