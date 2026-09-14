import Foundation
import Security

public struct GitHubClientID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              rawValue
              .allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") })
        else {
            throw GitHubError.invalidIdentifier
        }
        self.rawValue = rawValue
    }
}

public struct GitHubAccount: Hashable, Codable, Sendable {
    public let userID: Int
    public let login: String

    public init(userID: Int, login: String) {
        self.userID = userID
        self.login = login
    }
}

/// Native-only credential data. The host must exclude this module from runtime export.
public struct GitHubCredential: Codable, Sendable, CustomStringConvertible {
    public let account: GitHubAccount
    public let expiresAt: Date?
    let accessToken: String

    public init(account: GitHubAccount, accessToken: String, expiresAt: Date?) {
        self.account = account
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public var description: String {
        "GitHubCredential(<redacted>)"
    }
}

public protocol GitHubCredentialStore: Sendable {
    func credential(for clientID: GitHubClientID) async throws -> GitHubCredential?
    func save(_ credential: GitHubCredential, for clientID: GitHubClientID) async throws
    func remove(for clientID: GitHubClientID) async throws
}

/// Stores credentials on this device only. Calls are serialized through this actor.
public actor GitHubKeychainCredentialStore: GitHubCredentialStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func credential(for clientID: GitHubClientID) throws -> GitHubCredential? {
        var query = query(clientID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else { throw GitHubError.invalidResponse }
        return try JSONDecoder().decode(GitHubCredential.self, from: data)
    }

    public func save(_ credential: GitHubCredential, for clientID: GitHubClientID) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query(clientID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let newItem = query(clientID).merging(attributes) { _, new in new }
            let inserted = SecItemAdd(newItem as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw KeychainError(status: inserted) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func remove(for clientID: GitHubClientID) throws {
        let status = SecItemDelete(query(clientID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func query(_ clientID: GitHubClientID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Porthole.GitHub.\(service)",
            kSecAttrAccount as String: clientID.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public struct KeychainError: Error, Sendable {
        public let status: OSStatus
    }
}
