@_spi(Testing) import ForemanCore
import Testing

@MainActor
struct LoginItemControllerTests {
    @Test func seedsEnabledStateFromTheBackend() {
        let off = LoginItemController(backend: LoginItemRecorder(isRegistered: false))
        #expect(!off.isEnabled)

        let on = LoginItemController(backend: LoginItemRecorder(isRegistered: true))
        #expect(on.isEnabled)
    }

    @Test func enablingRegistersAndDisablingUnregisters() throws {
        let recorder = LoginItemRecorder()
        let controller = LoginItemController(backend: recorder)

        try controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(recorder.registerCount == 1)

        // Re-enabling is a no-op: the backend isn't touched again.
        try controller.setEnabled(true)
        #expect(recorder.registerCount == 1)

        try controller.setEnabled(false)
        #expect(!controller.isEnabled)
        #expect(recorder.unregisterCount == 1)
    }

    @Test func aFailedRegistrationLeavesTheStateHonestlyOff() {
        let recorder = LoginItemRecorder(failure: LoginItemTestError())
        let controller = LoginItemController(backend: recorder)

        #expect(throws: LoginItemTestError.self) {
            try controller.setEnabled(true)
        }
        // The register attempt happened, but it failed — the observed value
        // must not read as "on".
        #expect(recorder.registerCount == 1)
        #expect(!controller.isEnabled)
    }

    @Test func refreshPicksUpAnOutOfBandChange() {
        let recorder = LoginItemRecorder(isRegistered: false)
        let controller = LoginItemController(backend: recorder)
        #expect(!controller.isEnabled)

        // Simulate the user enabling the login item in System Settings.
        try? recorder.register()
        #expect(!controller.isEnabled)

        controller.refresh()
        #expect(controller.isEnabled)
    }
}
