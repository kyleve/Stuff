import Testing
@testable import WhereCore

struct RecordingParticipationTests {
    @Test func recordingCarriesItsDeviceAndNewInstallationDefault() {
        let participation = RecordingParticipation.recording(
            device: .preview,
            defaultEnabledForNewInstallation: false,
        )

        #expect(participation.currentDevice == .preview)
        #expect(participation.defaultEnabledForNewInstallation == false)
        #expect(participation.supportsLocalRecording)
    }

    @Test func managementOnlyHasNoLocalRecordingCapability() {
        let participation = RecordingParticipation.managementOnly

        #expect(participation.currentDevice == nil)
        #expect(participation.defaultEnabledForNewInstallation == false)
        #expect(participation.supportsLocalRecording == false)
    }
}
