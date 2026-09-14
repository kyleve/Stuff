import CryptoKit
import Foundation
import PortholeCertificates
import Security

/// A native-only TLS identity. Private material never enters debugger values or remote messages.
public struct PortholeTLSIdentity: Sendable, Codable, CustomStringConvertible {
    public let certificateDER: Data
    private let privateKeyX963: Data

    public var fingerprint: Data {
        Data(SHA256.hash(data: certificateDER))
    }

    public var description: String {
        "PortholeTLSIdentity(<private key redacted>)"
    }

    public static func generate(name: String, at now: Date) throws -> Self {
        let material = try PortholeCertificates.generate(name: name, at: now)
        return Self(
            certificateDER: material.certificateDER,
            privateKeyX963: material.privateKeyX963,
        )
    }

    public func validate(at now: Date) throws {
        guard try PortholeCertificates.isValid(certificateDER: certificateDER, at: now) else {
            throw PortholeRemoteError.invalidIdentity
        }
        _ = try securityIdentity()
    }

    func securityIdentity() throws -> SecIdentity {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw PortholeRemoteError.invalidIdentity
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            privateKeyX963 as CFData,
            attributes as CFDictionary,
            &error,
        ) else {
            if let error { throw error.takeRetainedValue() }
            throw PortholeRemoteError.invalidIdentity
        }
        guard let identity = SecIdentityCreate(nil, certificate, key)
        else { throw PortholeRemoteError.invalidIdentity }
        return identity
    }
}

/// Stores local identities and peer pins in device-only Keychain items. The host supplies any
/// shared access group.
public struct PortholeRemoteKeychain: Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func identity(name: String, at now: Date) throws -> PortholeTLSIdentity {
        if let data = try read(account: "identity") {
            let identity = try JSONDecoder().decode(PortholeTLSIdentity.self, from: data)
            try identity.validate(at: now)
            return identity
        }
        let identity = try PortholeTLSIdentity.generate(name: name, at: now)
        let data = try JSONEncoder().encode(identity)
        // Create-only avoids replacing an identity that another client surface just established.
        var item = query(account: "identity")
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard let existing = try read(account: "identity")
            else { throw PortholeRemoteError.invalidIdentity }
            let winner = try JSONDecoder().decode(PortholeTLSIdentity.self, from: existing)
            try winner.validate(at: now)
            return winner
        }
        guard status == errSecSuccess else { throw PortholeRemoteError.keychain(status) }
        return identity
    }

    func read(account: String) throws -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PortholeRemoteError.keychain(status) }
        guard let data = result as? Data else { throw PortholeRemoteError.invalidIdentity }
        return data
    }

    func write(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(
            query(account: account) as CFDictionary,
            attributes as CFDictionary,
        )
        if status == errSecItemNotFound {
            let newItem = query(account: account).merging(attributes) { _, new in new }
            let inserted = SecItemAdd(newItem as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw PortholeRemoteError.keychain(inserted) }
        } else if status != errSecSuccess { throw PortholeRemoteError.keychain(status) }
    }

    private func query(account: String) -> [String: Any] {
        var result: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Porthole.Remote.\(service)",
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup { result[kSecAttrAccessGroup as String] = accessGroup }
        return result
    }
}
