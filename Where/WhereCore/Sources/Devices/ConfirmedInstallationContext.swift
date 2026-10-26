import Foundation

/// Installation identity and explicit local consent required to assemble recording services.
/// An enabled interval always carries its cutoff. This is independent of account ownership.
public struct ConfirmedInstallationContext: Sendable, Equatable {
    public enum RecordingChoice: Sendable, Hashable {
        case off
        case on(enabledAt: Date)

        public var isEnabled: Bool {
            switch self {
                case .off: false
                case .on: true
            }
        }
    }

    public private(set) var recordingAccount: RecordingAccountBinding?

    public func settingRecordingAccount(_ binding: RecordingAccountBinding?) -> Self {
        var result = self
        result.recordingAccount = binding
        return result
    }

    public let currentDevice: CurrentRecordingDevice
    public let registeredAt: Date
    public let recordingChoice: RecordingChoice
    public let recordingControl: RecordingInstallationControl

    public init(
        currentDevice: CurrentRecordingDevice,
        registeredAt: Date,
        recordingChoice: RecordingChoice,
        recordingControl: RecordingInstallationControl,
    ) {
        self.currentDevice = currentDevice
        self.registeredAt = registeredAt
        self.recordingChoice = recordingChoice
        self.recordingControl = recordingControl
    }

    public var automaticRecordingEnabled: Bool {
        recordingChoice.isEnabled
    }

    public var recordingEnabledAt: Date? {
        switch recordingChoice {
            case .off: nil
            case let .on(enabledAt): enabledAt
        }
    }

    /// The persistence layer also represents installations waiting for first confirmation.
    public var context: InstallationRecordingContext {
        let choice: InstallationRecordingContext.RecordingChoice = switch recordingChoice {
            case .off: .off
            case let .on(enabledAt): .on(enabledAt: enabledAt)
        }
        return .init(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            recordingChoice: choice,
            isRejoining: false,
        )
        .settingRecordingControl(recordingControl)
        .settingRecordingAccount(recordingAccount)
    }

    /// Preserve the current On interval when Settings repeats the same choice.
    public func settingAutomaticRecordingEnabled(_ enabled: Bool, at date: Date) -> Self {
        let choice: RecordingChoice = enabled ? .on(enabledAt: recordingEnabledAt ?? date) : .off
        return .init(
            currentDevice: currentDevice,
            registeredAt: registeredAt,
            recordingChoice: choice,
            recordingControl: recordingControl,
        ).settingRecordingAccount(recordingAccount)
    }

    @_spi(Demo) public static let demo = InstallationRecordingContext.demo
        .confirmingInitialRecording(isEnabled: true)
    @_spi(Testing) public static let testing = InstallationRecordingContext.testing
        .confirmingInitialRecording(isEnabled: true)
}
