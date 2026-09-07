import Foundation
import os
import Security

/// A raw Keychain Services failure. Missing items are represented by `nil`,
/// while inaccessible or malformed items remain observable errors.
public struct KeychainError: LocalizedError, Equatable, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var isInteractionNotAllowed: Bool {
        status == errSecInteractionNotAllowed
    }

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
        return "\(message) (OSStatus \(status))"
    }
}

/// When a stored item is available relative to device lock state.
public enum KeychainAccessibility: Sendable, Hashable {
    case whenUnlocked
    case afterFirstUnlock

    var securityValue: CFString {
        switch self {
            case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
            case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        }
    }
}

/// Storage boundary for one opaque generic-password item.
public protocol KeychainStore: Sendable {
    func read() throws -> Data?
    func create(_ data: Data) throws
    func write(_ data: Data) throws
    func remove() throws
}

extension KeychainStore {
    public func readString() throws -> String? {
        guard let data = try read() else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return value
    }

    public func write(_ value: String) throws {
        try write(Data(value.utf8))
    }
}

/// A generic-password item identified by an explicit service and account.
public struct SystemKeychainStore: KeychainStore, Sendable {
    public let service: String
    public let account: String
    public let accessibility: KeychainAccessibility
    public let synchronizesThroughICloud: Bool

    public init(
        service: String,
        account: String,
        accessibility: KeychainAccessibility,
        synchronizesThroughICloud: Bool,
    ) {
        self.service = service
        self.account = account
        self.accessibility = accessibility
        self.synchronizesThroughICloud = synchronizesThroughICloud
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if synchronizesThroughICloud {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        return query
    }

    public func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                guard let data = item as? Data else {
                    throw KeychainError(status: errSecDecode)
                }
                return data
            case errSecItemNotFound:
                return nil
            default:
                throw KeychainError(status: status)
        }
    }

    public func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                do {
                    try create(data)
                } catch let error as KeychainError where error.status == errSecDuplicateItem {
                    // A concurrent writer may have inserted the item between
                    // update and add. Preserve upsert semantics by retrying the
                    // update rather than replacing the caller-visible contract
                    // with a spurious duplicate failure.
                    let retryStatus = SecItemUpdate(
                        baseQuery as CFDictionary,
                        attributes as CFDictionary,
                    )
                    guard retryStatus == errSecSuccess else {
                        throw KeychainError(status: retryStatus)
                    }
                }
            default:
                throw KeychainError(status: updateStatus)
        }
    }

    /// Inserts only when no matching item exists. Callers that mint stable
    /// secrets use this operation so a synchronized winner is never overwritten.
    public func create(_ data: Data) throws {
        var query = baseQuery
        query[kSecAttrAccessible as String] = accessibility.securityValue
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    public func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

/// Deterministic Keychain storage for consumers' unit tests.
@_spi(Testing)
public final class InMemoryKeychainStore: KeychainStore {
    private let data: OSAllocatedUnfairLock<Data?>
    private let failure: KeychainError?

    public init(data: Data? = nil, failure: KeychainError? = nil) {
        self.data = OSAllocatedUnfairLock(initialState: data)
        self.failure = failure
    }

    public func read() throws -> Data? {
        if let failure { throw failure }
        return data.withLock { $0 }
    }

    public func write(_ newValue: Data) throws {
        if let failure { throw failure }
        data.withLock { $0 = newValue }
    }

    public func create(_ newValue: Data) throws {
        if let failure { throw failure }
        try data.withLock { value in
            guard value == nil else {
                throw KeychainError(status: errSecDuplicateItem)
            }
            value = newValue
        }
    }

    public func remove() throws {
        if let failure { throw failure }
        data.withLock { $0 = nil }
    }
}
