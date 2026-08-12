import Observation
import WhereCore

/// Presentation and acknowledgement state for the Settings recording-configuration warning.
@MainActor
@Observable
final class RecordingConfigurationWarningModel {
    /// Narrow adapter from the session coordinator to the inputs this presentation model needs.
    @MainActor
    struct Source {
        private let session: WhereSession

        init(session: WhereSession) {
            self.session = session
        }

        var preferences: WherePreferences {
            session.preferences
        }

        var localInputs: LocalInputs {
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

        func condition(for inputs: LocalInputs) async throws
            -> RecordingConfigurationWarningCondition
        {
            let devices = try await session.recordingDevices()
            return RecordingConfigurationWarningCondition(
                currentDevice: session.services.recording.currentDevice,
                devices: devices.map(\.device),
                automaticRecordingEnabled: inputs.automaticRecordingEnabled,
                authorizationStatus: inputs.authorizationStatus,
                now: session.now(),
            )
        }

        func dataChangeUpdates() -> AsyncStream<Void> {
            session.services.dataChangeUpdates()
        }
    }

    struct LocalInputs: Hashable {
        let automaticRecordingEnabled: Bool?
        let authorizationStatus: LocationAuthorizationStatus
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

    /// Refresh when either local recording state changes or synced device authority changes.
    /// The sequence prevents a slower, older device-list read from overwriting a newer tuple.
    func refresh(_ inputs: LocalInputs, from source: Source) async {
        let (sequence, overflow) = refreshSequence.addingReportingOverflow(1)
        precondition(!overflow, "Recording warning refresh sequence exhausted UInt64.")
        refreshSequence = sequence
        do {
            let condition = try await source.condition(for: inputs)
            guard sequence == refreshSequence else { return }
            register(isWarningConditionActive: condition.isActive)
        } catch {
            guard sequence == refreshSequence else { return }
            Self.logger(attachments: [.error(error, name: "recording-warning-error")]) {
                .authorityLoadFailed(description: error.localizedDescription)
            }
        }
    }

    /// Keep the primary-device decision live as other installations check in, stop, or disappear.
    func observeAuthorityChanges(from source: Source) async {
        let updates = source.dataChangeUpdates()
        for await _ in updates {
            guard !Task.isCancelled else { return }
            await refresh(source.localInputs, from: source)
        }
    }

    func register(isWarningConditionActive: Bool) {
        registration.register(isWarningConditionActive: isWarningConditionActive)
        preferences.recordingConfigurationWarningRegistration = registration
        isPresented = registration.requiresWarning
    }

    func dismiss() {
        registration.acknowledgeCurrentGeneration()
        preferences.recordingConfigurationWarningRegistration = registration
        isPresented = registration.requiresWarning
    }
}
