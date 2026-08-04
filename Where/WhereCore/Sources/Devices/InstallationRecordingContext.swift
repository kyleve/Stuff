import Foundation

/// Device-local state that gives one installation a stable recording identity.
///
/// The whole value is persisted outside backed-up preferences. A restored device
/// therefore gets a new identity and must confirm its own initial recording
/// choice, while repeated launches of the same installation reuse both the
/// identity and its explicitly chosen local automatic-recording preference.
public struct InstallationRecordingContext: Sendable, Hashable {
    public enum RecordingChoice: Sendable, Hashable {
        case unconfirmed
        case off
        case on(enabledAt: Date)
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
        guard case let .on(enabledAt) = recordingChoice else { return nil }
        return enabledAt
    }

    /// The safe default shown until this installation confirms a choice.
    public var recommendedRecordingEnabled: Bool {
        !isRejoining && currentDevice.kind.recommendsAutomaticRecording
    }

    /// Return the confirmed form of a newly proposed context.
    public func confirmingInitialRecording(isEnabled: Bool) -> InstallationRecordingContext {
        precondition(
            recordingChoice == .unconfirmed,
            "An installation's initial recording choice can only be confirmed once.",
        )
        return InstallationRecordingContext(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            recordingChoice: isEnabled ? .on(enabledAt: registeredAt) : .off,
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
            recordingEnabledAt.map(RecordingChoice.on(enabledAt:))
                ?? .on(enabledAt: date)
        } else {
            .off
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
    public static let demo = InstallationRecordingContext(
        currentDevice: CurrentRecordingDevice(
            id: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000D0")!,
            ),
            systemName: "Demo iPhone",
            kind: .phone,
        ),
        registeredAt: Date(timeIntervalSinceReferenceDate: 0),
        recordingChoice: .on(enabledAt: Date(timeIntervalSinceReferenceDate: 0)),
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
        recordingChoice: .on(enabledAt: Date(timeIntervalSinceReferenceDate: 0)),
        isRejoining: false,
    )
}
