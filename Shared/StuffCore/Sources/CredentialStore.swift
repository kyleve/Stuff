import Foundation
import Security
#if DEBUG
    import Synchronization
#endif

/// A stable account name for a credential stored by an app-specific service.
public struct CredentialKey: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A credential key must not be empty")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

/// Binary credential storage. Callers own any string or token encoding.
public protocol CredentialStore: Sendable {
    func data(for key: CredentialKey) throws -> Data?
    func set(_ data: Data, for key: CredentialKey) throws
    func remove(_ key: CredentialKey) throws
}

/// A typed Keychain failure carrying the status returned by Security.framework.
public struct CredentialStoreError: LocalizedError, Equatable, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
        return "\(message) (OSStatus \(status))"
    }
}

/// A generic-password Keychain store namespaced by one app-owned service.
public struct SystemCredentialStore: CredentialStore {
    private let service: String

    public init(service: String) {
        precondition(!service.isEmpty, "A credential service must not be empty")
        self.service = service
    }

    public func data(for key: CredentialKey) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                guard let data = item as? Data else {
                    throw CredentialStoreError(status: errSecDecode)
                }
                return data
            case errSecItemNotFound:
                return nil
            default:
                throw CredentialStoreError(status: status)
        }
    }

    public func set(_ data: Data, for key: CredentialKey) throws {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var addQuery = query
                addQuery[kSecValueData as String] = data
                addQuery[kSecAttrAccessible as String] =
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw CredentialStoreError(status: addStatus)
                }
            default:
                throw CredentialStoreError(status: updateStatus)
        }
    }

    public func remove(_ key: CredentialKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError(status: status)
        }
    }

    private func baseQuery(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}

#if DEBUG
    /// A mutex-protected credential store for unit tests and previews.
    @_spi(Testing)
    public final class InMemoryCredentialStore: CredentialStore {
        private struct State {
            var values: [CredentialKey: Data]
        }

        private let state: Mutex<State>
        private let failure: CredentialStoreError?

        public init(
            values: [CredentialKey: Data] = [:],
            failure: CredentialStoreError? = nil,
        ) {
            state = Mutex(State(values: values))
            self.failure = failure
        }

        public func data(for key: CredentialKey) throws -> Data? {
            if let failure { throw failure }
            return state.withLock { $0.values[key] }
        }

        public func set(_ data: Data, for key: CredentialKey) throws {
            if let failure { throw failure }
            state.withLock { $0.values[key] = data }
        }

        public func remove(_ key: CredentialKey) throws {
            if let failure { throw failure }
            state.withLock { $0.values[key] = nil }
        }
    }
#endif
