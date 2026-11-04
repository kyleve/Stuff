import Foundation

/// Device-local state that gives one installation a stable recording identity.
///
/// Keychain storage owns identity; a backup-excluded sidecar owns consent and recovery.
/// A surviving same-device identity requires fresh consent after its sidecar disappears.
/// Ordinary relaunches and in-app imports preserve both.
public struct InstallationRecordingContext: Sendable, Hashable {
    public enum SetupCompletion: Sendable, Hashable {
        case pending
        case complete
    }

    public enum RecordingChoice: Sendable, Hashable {
        case unconfirmed
        case off(setup: SetupCompletion)
        case on(enabledAt: Date, setup: SetupCompletion)

        var completion: SetupCompletion {
            switch self {
                case .unconfirmed: .pending
                case let .off(setup), let .on(_, setup): setup
            }
        }
    }

    public let currentDevice: CurrentRecordingDevice
    /// Stable creation time for this installation's immutable device profile.
    public let registeredAt: Date
    public let recordingChoice: RecordingChoice
    /// Whether this identity was created by the explicit rejoin flow.
    public let isRejoining: Bool

    public init(
        currentDevice: CurrentRecordingDevice,
        registeredAt: Date,
        recordingChoice: RecordingChoice,
        isRejoining: Bool,
    ) {
        self.currentDevice = currentDevice
        self.registeredAt = registeredAt
        self.recordingChoice = recordingChoice
        self.isRejoining = isRejoining
    }

    /// This installation's explicit local choice. `nil` means onboarding has not confirmed it.
    public var automaticRecordingEnabled: Bool? {
        switch recordingChoice {
            case .unconfirmed: nil
            case .off: false
            case .on: true
        }
    }

    /// Earliest historical location accepted for the current On interval.
    public var recordingEnabledAt: Date? {
        guard case let .on(enabledAt, _) = recordingChoice else { return nil }
        return enabledAt
    }

    public var hasCompletedSetup: Bool {
        recordingChoice.completion == .complete
    }

    /// Confirmation permits service assembly; only a completed setup can skip the next gate.
    public func completingSetup() -> Self {
        precondition(recordingChoice != .unconfirmed, "Setup requires confirmed recording consent.")
        let choice: RecordingChoice = if let recordingEnabledAt {
            .on(enabledAt: recordingEnabledAt, setup: .complete)
        } else {
            .off(setup: .complete)
        }
        return Self(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            recordingChoice: choice,
            isRejoining: false,
        )
    }

    /// The safe default shown until this installation confirms a choice.
    public var recommendedRecordingEnabled: Bool {
        !isRejoining && currentDevice.kind.recommendsAutomaticRecording
    }

    /// Return the confirmed form of a newly proposed context.
    public func confirmingInitialRecording(
        isEnabled: Bool,
        at date: Date,
    ) -> InstallationRecordingContext {
        precondition(
            recordingChoice == .unconfirmed,
            "An installation's initial recording choice can only be confirmed once.",
        )
        return InstallationRecordingContext(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            recordingChoice: isEnabled ? .on(enabledAt: date, setup: .pending) :
                .off(setup: .pending),
            isRejoining: false,
        )
    }

    /// Return a copy carrying a later local Settings choice.
    public func settingAutomaticRecordingEnabled(_ isEnabled: Bool, at date: Date) -> Self {
        precondition(
            recordingChoice != .unconfirmed,
            "Automatic recording must be confirmed before Settings can change it.",
        )
        let updatedChoice: RecordingChoice = if isEnabled {
            .on(enabledAt: recordingEnabledAt ?? date, setup: recordingChoice.completion)
        } else {
            .off(setup: recordingChoice.completion)
        }
        return InstallationRecordingContext(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            recordingChoice: updatedChoice,
            isRejoining: false,
        )
    }

    /// The throwaway identity used by demo mode. It is intentionally distinct
    /// from test fixtures and never belongs to the real installation sidecar.
    @_spi(Demo)
    public static let demo = InstallationRecordingContext(
        currentDevice: CurrentRecordingDevice(
            id: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000D0")!,
            ),
            systemName: "Demo iPhone",
            kind: .phone,
        ),
        registeredAt: Date(timeIntervalSinceReferenceDate: 0),
        recordingChoice: .on(enabledAt: Date(timeIntervalSinceReferenceDate: 0), setup: .complete),
        isRejoining: false,
    )

    /// Deterministic context for tests and previews that do not care which
    /// installation is current.
    @_spi(Testing)
    public static let testing = InstallationRecordingContext(
        currentDevice: CurrentRecordingDevice(
            id: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            ),
            systemName: "iPhone",
            kind: .phone,
        ),
        registeredAt: Date(timeIntervalSinceReferenceDate: 0),
        recordingChoice: .on(enabledAt: Date(timeIntervalSinceReferenceDate: 0), setup: .complete),
        isRejoining: false,
    )
}
