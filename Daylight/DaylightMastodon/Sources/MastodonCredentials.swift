import Foundation
import Security

public protocol MastodonCredentials: Sendable {
    func read() throws -> MastodonCredential?
    func write(_ credential: MastodonCredential) throws
}

public struct KeychainMastodonCredentials: MastodonCredentials {
    public init() {}
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.stuff.daylight.mastodon",
            kSecAttrAccount as String: "token",
        ]
    }

    public func read() throws -> MastodonCredential? {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data
        else { throw MastodonError.credentialStore(status) }
        return try JSONDecoder().decode(MastodonCredential.self, from: data)
    }

    public func write(_ credential: MastodonCredential) throws {
        let values: [String: Any] = try [kSecValueData as String: JSONEncoder().encode(credential)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query.merging(values) { _, new in new }
            addition[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else { throw MastodonError.credentialStore(added) }
        } else if status != errSecSuccess { throw MastodonError.credentialStore(status) }
    }
}
