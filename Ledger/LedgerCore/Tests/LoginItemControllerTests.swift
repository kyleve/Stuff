@_spi(Testing) import LedgerCore
import Testing

@MainActor
struct LoginItemControllerTests {
    @Test func seedsStateFromTheBackend() {
        let off = LoginItemController(backend: LoginItemRecorder(status: .notRegistered))
        #expect(!off.isEnabled)
        #expect(!off.needsApproval)

        let on = LoginItemController(backend: LoginItemRecorder(status: .enabled))
        #expect(on.isEnabled)
        #expect(!on.needsApproval)
    }

    @Test func requiresApprovalReadsAsEnabledButPending() {
        let controller = LoginItemController(backend: LoginItemRecorder(status: .requiresApproval))

        // Registered-but-pending is "on" for the toggle — not off — with a
        // flag the UI can use to nudge the user toward System Settings.
        #expect(controller.isEnabled)
        #expect(controller.needsApproval)
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

    @Test func disablingAPendingItemStillUnregisters() throws {
        let recorder = LoginItemRecorder(status: .requiresApproval)
        let controller = LoginItemController(backend: recorder)

        try controller.setEnabled(false)
        #expect(recorder.unregisterCount == 1)
        #expect(!controller.isEnabled)
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
        let recorder = LoginItemRecorder(status: .notRegistered)
        let controller = LoginItemController(backend: recorder)
        #expect(!controller.isEnabled)

        // Simulate the user enabling the login item in System Settings.
        try? recorder.register()
        #expect(!controller.isEnabled)

        controller.refresh()
        #expect(controller.isEnabled)
    }

    @Test func openSystemSettingsForwardsToTheBackend() {
        let recorder = LoginItemRecorder()
        let controller = LoginItemController(backend: recorder)

        controller.openSystemSettingsLoginItems()
        #expect(recorder.openCount == 1)
    }
}
