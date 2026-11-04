import Foundation
import Security

/// Nonsynchronizing, device-only recording identity. Reads distinguish absence from every
/// Security-framework failure. Rotation atomically matches the previous identity attribute.
@MainActor
public final class KeychainRecordingIdentityStore: RecordingIdentityStoring {
    public enum StorageError: Error, Equatable {
        case invalidIdentity
        case corruptPayload
        case unsafeAttributes
        case reusedIdentity
        case keychain(OSStatus)
    }

    private let service: String
    private let client: any RecordingIdentityKeychainClient
    private static let account = "recording-identity"

    public convenience init(service: String) {
        self.init(service: service, client: SystemRecordingIdentityKeychainClient())
    }

    @_spi(Testing)
    public init(service: String, client: any RecordingIdentityKeychainClient) {
        precondition(!service.isEmpty, "Recording identity requires an explicit Keychain service.")
        self.service = service
        self.client = client
    }

    public func load() throws -> InstallationRecordingIdentity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let result = client.copyMatching(query)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess else { throw StorageError.keychain(result.status) }
        guard let attributes = result.attributes,
              let data = attributes[kSecValueData as String] as? Data
        else { throw StorageError.corruptPayload }
        guard attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            attributes[kSecAttrSynchronizable as String] as? Bool == false
        else { throw StorageError.unsafeAttributes }
        let identity = try JSONDecoder().decode(InstallationRecordingIdentity.self, from: data)
        try validate(identity)
        guard attributes[kSecAttrGeneric as String] as? Data == identityData(identity.deviceID)
        else { throw StorageError.corruptPayload }
        return identity
    }

    public func create(_ identity: InstallationRecordingIdentity) throws {
        try validate(identity)
        var attributes = baseQuery
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrGeneric as String] = identityData(identity.deviceID)
        attributes[kSecValueData as String] = try JSONEncoder().encode(identity)
        let status = client.add(attributes)
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
    }

    public func replace(
        _ identity: InstallationRecordingIdentity,
        expectedDeviceID: RecordingDeviceID,
    ) throws {
        try validate(identity)
        guard identity.deviceID != expectedDeviceID else { throw StorageError.reusedIdentity }
        var query = baseQuery
        query[kSecAttrGeneric as String] = identityData(expectedDeviceID)
        let attributes: [String: Any] = try [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrGeneric as String: identityData(identity.deviceID),
            kSecValueData as String: JSONEncoder().encode(identity),
        ]
        let status = client.update(query, attributes: attributes)
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func identityData(_ deviceID: RecordingDeviceID) -> Data {
        Data(deviceID.rawValue.uuidString.utf8)
    }

    private func validate(_ identity: InstallationRecordingIdentity) throws {
        guard identity.registeredAt.timeIntervalSinceReferenceDate.isFinite else {
            throw StorageError.invalidIdentity
        }
    }
}
