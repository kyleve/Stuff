import Foundation
import Security

/// Credentials are resolved only at the native provider boundary.
public protocol PortholeAgentCredentialStore: Sendable {
    func apiKey(for provider: PortholeAgentProvider) throws -> String
}

public protocol PortholeAgentCredentialEditing: PortholeAgentCredentialStore {
    func store(apiKey: String, for provider: PortholeAgentProvider) throws
    func remove(for provider: PortholeAgentProvider) throws
}

/// Stores provider keys in this device's unlocked Keychain. No key is exported to tools.
public struct PortholeAgentKeychain: PortholeAgentCredentialEditing, Sendable {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func store(apiKey: String, for provider: PortholeAgentProvider) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PortholeAgentError.missingCredential(provider) }
        let value = Data(key.utf8)
        let query = query(for: provider)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: value] as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecValueData] = value
            addition[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else { throw PortholeAgentError.credentialStorage(added) }
        } else if status != errSecSuccess {
            throw PortholeAgentError.credentialStorage(status)
        }
    }

    public func remove(for provider: PortholeAgentProvider) throws {
        let status = SecItemDelete(query(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PortholeAgentError.credentialStorage(status)
        }
    }

    public func apiKey(for provider: PortholeAgentProvider) throws -> String {
        var query = query(for: provider)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw PortholeAgentError.missingCredential(provider) }
        guard status == errSecSuccess else { throw PortholeAgentError.credentialStorage(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else {
            throw PortholeAgentError.missingCredential(provider)
        }
        return key
    }

    private func query(for provider: PortholeAgentProvider) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.rawValue,
        ]
    }
}
