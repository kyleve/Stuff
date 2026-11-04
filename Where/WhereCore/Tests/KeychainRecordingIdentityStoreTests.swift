import Foundation
import Security
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct KeychainRecordingIdentityStoreTests {
    @Test func realKeychainRetainsIdentityAndRejectsStaleRotation() throws {
        let service = "WhereCoreTests.RecordingIdentity.\(UUID().uuidString)"
        defer {
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "recording-identity",
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
        let store = KeychainRecordingIdentityStore(service: service)
        #expect(try store.load() == nil)
        let original = RecordingIdentityTestSupport.identity()
        try store.create(original)
        #expect(try store.load() == original)
        let replacement = RecordingIdentityTestSupport.identity(creation: .reset)
        #expect(throws: KeychainRecordingIdentityStore.StorageError.keychain(errSecDuplicateItem)) {
            try store.create(replacement)
        }
        #expect(try store.load() == original)
        try store.replace(replacement, expectedDeviceID: original.deviceID)
        #expect(try KeychainRecordingIdentityStore(service: service).load() == replacement)
        #expect(throws: KeychainRecordingIdentityStore.StorageError.keychain(errSecItemNotFound)) {
            try store.replace(
                RecordingIdentityTestSupport.identity(creation: .rejoin),
                expectedDeviceID: original.deviceID,
            )
        }
        #expect(try store.load() == replacement)
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable])
    func inaccessibleIdentityNeverBecomesAbsenceOrCreatesAReplacement(status: OSStatus) throws {
        let client = RecordingIdentityTestSupport.Client(result: .init(
            status: status,
            attributes: nil,
        ))
        let store = KeychainRecordingIdentityStore(service: "test-identity", client: client)
        #expect(throws: KeychainRecordingIdentityStore.StorageError.keychain(status)) {
            try store.load()
        }
        #expect(client.additions.isEmpty)
        #expect(client.updates.isEmpty)
        #expect(client.readQueries.count == 1)
    }

    @Test func confirmedAbsenceIsReadOnly() throws {
        let client = RecordingIdentityTestSupport.Client(
            result: .init(status: errSecItemNotFound, attributes: nil),
        )
        let store = KeychainRecordingIdentityStore(service: "test-identity", client: client)
        #expect(try store.load() == nil)
        #expect(client.additions.isEmpty)
        #expect(client.updates.isEmpty)
    }

    @Test func corruptOrTransferableItemsCannotBeAdopted() throws {
        let identity = RecordingIdentityTestSupport.identity()
        var attributes = try RecordingIdentityTestSupport.attributes(identity)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let client = RecordingIdentityTestSupport.Client(result: .init(
            status: errSecSuccess,
            attributes: attributes,
        ))
        let store = KeychainRecordingIdentityStore(service: "test-identity", client: client)
        #expect(throws: KeychainRecordingIdentityStore.StorageError.unsafeAttributes) {
            try store.load()
        }
        attributes = try RecordingIdentityTestSupport.attributes(identity)
        attributes[kSecAttrGeneric as String] = Data("another-identity".utf8)
        client.result = .init(status: errSecSuccess, attributes: attributes)
        #expect(throws: KeychainRecordingIdentityStore.StorageError.corruptPayload) {
            try store.load()
        }
        attributes[kSecValueData as String] = Data("incomplete".utf8)
        client.result = .init(status: errSecSuccess, attributes: attributes)
        #expect(throws: DecodingError.self) { try store.load() }
        #expect(client.additions.isEmpty)
        #expect(client.updates.isEmpty)
    }

    @Test func writesUseDeviceOnlyProtectionAndPreserveTheKeychainError() throws {
        let client = RecordingIdentityTestSupport.Client(result: .init(
            status: errSecItemNotFound,
            attributes: nil,
        ))
        let store = KeychainRecordingIdentityStore(service: "explicit-service", client: client)
        client.writeStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainRecordingIdentityStore.StorageError
            .keychain(errSecInteractionNotAllowed))
        {
            try store.create(RecordingIdentityTestSupport.identity())
        }
        let attributes = try #require(client.additions.first)
        #expect(attributes[kSecAttrService as String] as? String == "explicit-service")
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func rotationRequiresANewIdentity() throws {
        let identity = RecordingIdentityTestSupport.identity()
        let client = RecordingIdentityTestSupport.Client(result: .init(
            status: errSecSuccess,
            attributes: nil,
        ))
        let store = KeychainRecordingIdentityStore(service: "test-identity", client: client)
        #expect(throws: KeychainRecordingIdentityStore.StorageError.reusedIdentity) {
            try store.replace(identity, expectedDeviceID: identity.deviceID)
        }
        #expect(client.updates.isEmpty)
    }
}
