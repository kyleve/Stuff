import Foundation

/// Device-local state that gives one installation a stable recording identity.
///
/// The whole value is persisted outside backed-up preferences. A restored device
/// therefore gets a new identity and must confirm its own initial recording
/// choice, while repeated launches of the same installation reuse both the
/// identity and the complete immutable payload inputs for its first synced
/// device profile and policy event.
public struct InstallationRecordingContext: Sendable, Hashable {
    /// The explicitly confirmed first policy for this installation, including
    /// the timestamp reused whenever its immutable event must be recreated.
    public struct InitialRecordingChoice: Sendable, Hashable {
        public let isEnabled: Bool
        public let policyChangeID: UUID
        public let confirmedAt: Date

        public init(
            isEnabled: Bool,
            policyChangeID: UUID,
            confirmedAt: Date,
        ) {
            self.isEnabled = isEnabled
            self.policyChangeID = policyChangeID
            self.confirmedAt = confirmedAt
        }
    }

    public let currentDevice: CurrentRecordingDevice
    /// Stable creation time for this installation's immutable device profile.
    public let registeredAt: Date
    public let initialRecordingChoice: InitialRecordingChoice?

    public init(
        currentDevice: CurrentRecordingDevice,
        registeredAt: Date,
        initialRecordingChoice: InitialRecordingChoice?,
    ) {
        self.currentDevice = currentDevice
        self.registeredAt = registeredAt
        self.initialRecordingChoice = initialRecordingChoice
    }

    /// The safe default shown until this installation confirms a choice.
    public var recommendedRecordingEnabled: Bool {
        currentDevice.kind.recommendsAutomaticRecording
    }

    /// Return the confirmed form of a newly proposed context, freezing every
    /// value needed to recreate the first policy event byte-for-byte.
    public func confirmingInitialRecording(
        isEnabled: Bool,
        policyChangeID: UUID,
        confirmedAt: Date,
    ) -> InstallationRecordingContext {
        precondition(
            initialRecordingChoice == nil,
            "An installation's initial recording choice can only be confirmed once.",
        )
        return InstallationRecordingContext(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            initialRecordingChoice: InitialRecordingChoice(
                isEnabled: isEnabled,
                policyChangeID: policyChangeID,
                confirmedAt: confirmedAt,
            ),
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
        initialRecordingChoice: InitialRecordingChoice(
            isEnabled: true,
            policyChangeID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            confirmedAt: Date(timeIntervalSinceReferenceDate: 1),
        ),
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
        initialRecordingChoice: InitialRecordingChoice(
            isEnabled: true,
            policyChangeID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            confirmedAt: Date(timeIntervalSinceReferenceDate: 1),
        ),
    )
}
