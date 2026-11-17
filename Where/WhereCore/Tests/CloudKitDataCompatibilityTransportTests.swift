import CloudKit
import Testing
@testable import WhereCore

struct CloudKitDataCompatibilityTransportTests {
    @Test func onlyConfirmedNoAccountUsesLocalModeWithoutLookingUpIdentity() async throws {
        let domain = try await CloudKitDataCompatibilityTransport.resolveDomain(
            status: .noAccount,
            containerIdentifier: "iCloud.test",
            userRecordName: {
                Issue.record("A missing account has no user record to look up")
                throw CKError(.notAuthenticated)
            },
        )
        #expect(domain == .local)
    }

    @Test(arguments: [CKAccountStatus.restricted, .couldNotDetermine, .temporarilyUnavailable])
    func unavailableAccountNeverBecomesLocal(status: CKAccountStatus) async {
        await #expect(throws: CKError.self) {
            try await CloudKitDataCompatibilityTransport.resolveDomain(
                status: status,
                containerIdentifier: "iCloud.test",
                userRecordName: {
                    Issue.record("Unavailable accounts must not look up user identity")
                    return "unused"
                },
            )
        }
    }

    @Test func cloudIdentityIncludesItsContainerAndPropagatesAuthenticationFailure() async throws {
        let domain = try await CloudKitDataCompatibilityTransport.resolveDomain(
            status: .available,
            containerIdentifier: "iCloud.test",
            userRecordName: { "user-a" },
        )
        #expect(domain == .cloud(.init(
            containerIdentifier: "iCloud.test",
            userRecordName: "user-a",
        )))
        await #expect(throws: CKError.self) {
            try await CloudKitDataCompatibilityTransport.resolveDomain(
                status: .available,
                containerIdentifier: "iCloud.test",
                userRecordName: { throw CKError(.notAuthenticated) },
            )
        }
    }
}
