import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingIdentityRecoveryPolicyTests {
    @Test func onlyTheLegacySidecarCanSeedAMissingKeychainIdentity() throws {
        let context = InstallationRecordingContext.testing
        #expect(try RecordingIdentityRecoveryPolicy.resolve(
            identity: nil,
            sidecar: .legacy(context),
        )
            == .adoptLegacy(context))
        #expect(try RecordingIdentityRecoveryPolicy.resolve(
            identity: nil,
            sidecar: .keychainBound(context),
        )
            == .newIdentity)
        #expect(try RecordingIdentityRecoveryPolicy.resolve(identity: nil, sidecar: .absent)
            == .newIdentity)
    }

    @Test func survivingIdentityRequiresRenewedConsentWhenTheSidecarIsAbsentOrDifferent() throws {
        let identity = InstallationRecordingIdentity(
            deviceID: RecordingDeviceID(rawValue: UUID()),
            registeredAt: .distantPast,
            creation: .initial,
        )
        #expect(try RecordingIdentityRecoveryPolicy.resolve(identity: identity, sidecar: .absent)
            == .reuse(identity, confirmedContext: nil))
        #expect(try RecordingIdentityRecoveryPolicy.resolve(
            identity: identity,
            sidecar: .keychainBound(.testing),
        )
            == .reuse(identity, confirmedContext: nil))
    }

    @Test func ordinaryUpdatesPreserveConsentButInterruptedResetRequiresCleanup() throws {
        let context = InstallationRecordingContext.testing
        let identity = InstallationRecordingIdentity(
            deviceID: context.currentDevice.id,
            registeredAt: context.registeredAt,
            creation: .initial,
        )
        #expect(try RecordingIdentityRecoveryPolicy.resolve(
            identity: identity,
            sidecar: .keychainBound(context),
        )
            == .reuse(identity, confirmedContext: context))
        let reset = InstallationRecordingIdentity(
            deviceID: RecordingDeviceID(rawValue: UUID()),
            registeredAt: .now,
            creation: .reset,
        )
        #expect(try RecordingIdentityRecoveryPolicy.resolve(
            identity: reset,
            sidecar: .keychainBound(context),
        )
            == .finishReset(reset))
    }

    @Test func oneIdentityCannotAcquireAConflictingRegistrationTime() throws {
        let context = InstallationRecordingContext.testing
        let identity = InstallationRecordingIdentity(
            deviceID: context.currentDevice.id,
            registeredAt: .now,
            creation: .initial,
        )
        #expect(throws: RecordingIdentityRecoveryPolicy.ValidationError.self) {
            try RecordingIdentityRecoveryPolicy.resolve(
                identity: identity,
                sidecar: .keychainBound(context),
            )
        }
    }
}
