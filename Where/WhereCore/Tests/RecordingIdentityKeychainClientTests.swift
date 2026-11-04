import Foundation
import Security
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct RecordingIdentityKeychainClientTests {
    @Test func missingItemRetainsSecurityStatusWithoutAnAttributePayload() {
        let result = SystemRecordingIdentityKeychainClient().copyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "WhereCoreTests.AbsentIdentity.\(UUID().uuidString)",
            kSecAttrAccount as String: "recording-identity",
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ])
        #expect(result.status == errSecItemNotFound)
        #expect(result.attributes == nil)
    }
}
