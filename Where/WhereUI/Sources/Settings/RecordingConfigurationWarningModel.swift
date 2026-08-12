import Foundation
import Observation
import WhereCore

/// Presentation and acknowledgement state for the Settings recording-configuration warning.
@MainActor
@Observable
final class RecordingConfigurationWarningModel {
    struct LocalInputs: Hashable {
        let automaticRecordingEnabled: Bool?
        let authorizationStatus: LocationAuthorizationStatus
    }

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
    private var refreshSequence: UInt64 = 0

    private static let logger = WhereLog.root(RecordingConfigurationWarningModelLog.self)

    init(preferences: WherePreferences) {
        self.preferences = preferences
        let registration = preferences.recordingConfigurationWarningRegistration
        self.registration = registration
        isPresented = registration.requiresWarning
    }

    func localInputs(for session: WhereSession) -> LocalInputs {
        let automaticRecordingEnabled: Bool? = if case let .applied(configuration) =
            session.recordingRuntimeState
        {
            configuration.localAutomaticRecordingEnabled
        } else {
            nil
        }
        return LocalInputs(
            automaticRecordingEnabled: automaticRecordingEnabled,
            authorizationStatus: session.authorizationStatus,
        )
    }

    /// Refresh when either local recording state changes or synced device authority changes.
    /// The sequence prevents a slower, older device-list read from overwriting a newer tuple.
    func refresh(_ inputs: LocalInputs, for session: WhereSession) async {
        let (sequence, overflow) = refreshSequence.addingReportingOverflow(1)
        precondition(!overflow, "Recording warning refresh sequence exhausted UInt64.")
        refreshSequence = sequence
        do {
            let devices = try await session.recordingDevices()
            guard sequence == refreshSequence else { return }
            register(Configuration(
                isPrimaryRecordingDevice: Self.isPrimaryRecordingDevice(
                    session.services.recording.currentDevice,
                    among: devices.map(\.device),
                    now: session.now(),
                ),
                automaticRecordingEnabled: inputs.automaticRecordingEnabled,
                authorizationStatus: inputs.authorizationStatus,
            ))
        } catch {
            guard sequence == refreshSequence else { return }
            Self.logger(attachments: [.error(error, name: "recording-warning-error")]) {
                .authorityLoadFailed(description: error.localizedDescription)
            }
        }
    }

    static func isPrimaryRecordingDevice(
        _ currentDevice: CurrentRecordingDevice,
        among devices: [RecordingDevice],
        now: Date,
    ) -> Bool {
        RecordingOnboardingRecommendation(
            for: currentDevice,
            devices: devices,
            now: now,
        ).isEnabled
    }

    /// Keep the primary-device decision live as other installations check in, stop, or disappear.
    func observeAuthorityChanges(for session: WhereSession) async {
        let updates = session.services.dataChangeUpdates()
        for await _ in updates {
            guard !Task.isCancelled else { return }
            await refresh(localInputs(for: session), for: session)
        }
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
