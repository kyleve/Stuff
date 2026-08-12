import Observation
import WhereCore

/// Presentation and acknowledgement state for the Settings recording-configuration warning.
@MainActor
@Observable
final class RecordingConfigurationWarningModel {
    struct Configuration: Hashable {
        let isPrimaryRecordingDevice: Bool
        let automaticRecordingEnabled: Bool?
        let authorizationStatus: LocationAuthorizationStatus

        var isWarningConditionActive: Bool {
            isPrimaryRecordingDevice
                && automaticRecordingEnabled == false
                && !authorizationStatus.allowsBackgroundTracking
        }
    }

    private let preferences: WherePreferences
    private var registration: RecordingConfigurationWarningRegistration
    private(set) var isPresented: Bool

    init(preferences: WherePreferences) {
        self.preferences = preferences
        let registration = preferences.recordingConfigurationWarningRegistration
        self.registration = registration
        isPresented = registration.requiresWarning
    }

    func configuration(for session: WhereSession) -> Configuration {
        let automaticRecordingEnabled: Bool? = if case let .applied(configuration) =
            session.recordingRuntimeState
        {
            configuration.localAutomaticRecordingEnabled
        } else {
            nil
        }
        return Configuration(
            isPrimaryRecordingDevice: session.services.recording.currentDevice.kind
                .recommendsAutomaticRecording,
            automaticRecordingEnabled: automaticRecordingEnabled,
            authorizationStatus: session.authorizationStatus,
        )
    }

    func register(_ configuration: Configuration) {
        registration.register(isWarningConditionActive: configuration.isWarningConditionActive)
        preferences.recordingConfigurationWarningRegistration = registration
        isPresented = registration.requiresWarning
    }

    func dismiss() {
        registration.acknowledgeCurrentGeneration()
        preferences.recordingConfigurationWarningRegistration = registration
        isPresented = registration.requiresWarning
    }
}
