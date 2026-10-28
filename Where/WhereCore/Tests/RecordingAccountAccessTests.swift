import CloudKit
import Testing
@testable import WhereCore

@MainActor
struct RecordingAccountAccessTests {
    @Test func identityResponseFromInvalidatedSessionCannotPersistTrust() async throws {
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let transport = CompatibilityTestTransport()
        let access = RecordingAccountAccess(installation: installation, transport: transport)
        let oldPermit = try await access.verify()
        try access.acceptAuthority(using: oldPermit)
        let gate = CompatibilityTestGate()
        await transport.holdNextIdentity(gate)
        let oldRequest = Task { try await access.verify() }
        await gate.waitUntilEntered()
        try access.invalidate()
        gate.resume()
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            _ = try await oldRequest.value
        }
        #expect(installation.onboardingContext
            .recordingAccount == .invalidated(.cloudKit(recordName: "account-a")))
        #expect(throws: DataCompatibilityError.accessRevoked) { try oldPermit.validate() }
        #expect(throws: RecordingAccountError.verificationRequired) {
            _ = try access.cachedSession()
        }
    }

    @Test func failedInvalidationWriteStillRevokesTheProcess() async throws {
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let transport = CompatibilityTestTransport()
        let access = RecordingAccountAccess(installation: installation, transport: transport)
        let permit = try await access.verify()
        try access.acceptAuthority(using: permit)
        installation.failsAccountWrite = true
        #expect(throws: RecordingCoordinationInstallation.WriteFailure.self) {
            try access.invalidate()
        }
        #expect(throws: DataCompatibilityError.accessRevoked) { try permit.validate() }
        #expect(throws: RecordingAccountError.verificationRequired) {
            _ = try access.cachedSession()
        }
        let restarted = RecordingAccountAccess(installation: installation, transport: transport)
        #expect(throws: RecordingAccountError.verificationRequired) {
            _ = try restarted.cachedSession()
        }
    }

    @Test func authenticationFailureCannotBecomeAnOfflineFallback() async throws {
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let transport = CompatibilityTestTransport()
        let access = RecordingAccountAccess(installation: installation, transport: transport)
        try await access.acceptAuthority(using: access.verify())
        await transport.setAvailability(.signedOut)
        await #expect(throws: CKError.self) { _ = try await access.verify() }
        await transport.setAvailability(.offline)
        await #expect(throws: CKError.self) { _ = try await access.verify() }
        #expect(throws: RecordingAccountError.verificationRequired) {
            _ = try access.cachedSession()
        }
    }
}
