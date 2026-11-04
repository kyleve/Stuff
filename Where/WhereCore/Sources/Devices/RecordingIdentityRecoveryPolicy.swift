/// Reconciles device-only identity with a backup-excluded consent/recovery sidecar. A missing
/// Keychain item is an explicit input; a failed Keychain read must never reach this policy.
public enum RecordingIdentityRecoveryPolicy {
    public enum Sidecar: Sendable {
        case absent
        case legacy(InstallationRecordingContext)
        case keychainBound(InstallationRecordingContext)

        var context: InstallationRecordingContext? {
            switch self {
                case .absent: nil
                case let .legacy(context), let .keychainBound(context): context
            }
        }
    }

    public enum Resolution: Hashable, Sendable {
        case newIdentity
        case adoptLegacy(InstallationRecordingContext)
        case reuse(InstallationRecordingIdentity, confirmedContext: InstallationRecordingContext?)
        case finishReset(InstallationRecordingIdentity)
    }

    public enum ValidationError: Error {
        case inconsistentRegistration
    }

    public static func resolve(
        identity: InstallationRecordingIdentity?,
        sidecar: Sidecar,
    ) throws -> Resolution {
        guard let identity else {
            switch sidecar {
                case let .legacy(context): return .adoptLegacy(context)
                case .absent, .keychainBound: return .newIdentity
            }
        }
        guard let context = sidecar.context else { return .reuse(identity, confirmedContext: nil) }
        if context.currentDevice.id == identity.deviceID {
            guard context.registeredAt == identity.registeredAt else {
                throw ValidationError.inconsistentRegistration
            }
            return .reuse(identity, confirmedContext: context)
        }
        if identity.creation == .reset { return .finishReset(identity) }
        return .reuse(identity, confirmedContext: nil)
    }
}
