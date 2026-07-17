import Foundation
import Security

/// A failure reading or writing the Keychain. Wraps the raw `OSStatus` so a
/// caller can log something actionable rather than swallowing the error.
public struct KeychainError: LocalizedError, Equatable, Sendable {
    public let status: OSStatus
    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
        return "\(message) (OSStatus \(status))"
    }
}

/// Stores a single secret string (Ledger's Admin API key) securely. The seam
/// is a protocol so tests use an in-memory fake — the real Keychain isn't
/// available in a hostless test process without a signed, entitled host.
public protocol KeychainStore: Sendable {
    /// The stored secret, or `nil` when nothing is stored. Throws
    /// ``KeychainError`` on an unexpected Keychain failure (a missing item is
    /// `nil`, not an error).
    func read() throws -> String?
    /// Stores `secret`, replacing any existing value. Passing an empty or
    /// whitespace-only string removes the item.
    func write(_ secret: String) throws
    /// Removes the stored secret, if any.
    func remove() throws
}

/// The production ``KeychainStore``: a generic-password item in the login
/// Keychain, keyed by `service`/`account`. Ledger isn't sandboxed (like the
/// old Foreman app), so it reaches the default login Keychain without a
/// keychain-access-group entitlement.
public struct SystemKeychainStore: KeychainStore {
    private let service: String
    private let account: String

    /// Defaults to the app's bundle-style service and a fixed account name;
    /// there is only ever one secret (the Admin API key).
    public init(service: String = "com.stuff.ledger", account: String = "admin-api-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                guard let data = item as? Data,
                      let string = String(data: data, encoding: .utf8)
                else {
                    return nil
                }
                return string
            case errSecItemNotFound:
                return nil
            default:
                throw KeychainError(status: status)
        }
    }

    public func write(_ secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove()
            return
        }

        let data = Data(trimmed.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var addQuery = baseQuery
                addQuery[kSecValueData as String] = data
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw KeychainError(status: addStatus)
                }
            default:
                throw KeychainError(status: updateStatus)
        }
    }

    public func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
