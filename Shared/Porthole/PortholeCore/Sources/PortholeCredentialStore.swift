import CryptoKit
import Foundation
import Security

/// One stored pairing without its secret: the pairing id and an opaque metadata
/// blob (each side encodes its own record type into it — `PairedHost` on the
/// device, `PairedApp` on the client).
public struct PortholeCredentialRecord: Sendable, Equatable {
    public var pairingID: UUID
    public var metadata: Data

    public init(pairingID: UUID, metadata: Data) {
        self.pairingID = pairingID
        self.metadata = metadata
    }
}

/// Persists pairing secrets (the per-pairing PSK) and a small metadata blob,
/// keyed by pairing id. Both the device and the Mac client store to it; the
/// production implementation is Keychain-backed, tests inject an in-memory
/// double. Failures throw — a credential that silently fails to load would read
/// as "not paired", so callers must see the difference.
public protocol PortholeCredentialStore: Sendable {
    func save(pairingID: UUID, key: SymmetricKey, metadata: Data) throws
    func key(for pairingID: UUID) throws -> SymmetricKey?
    func metadata(for pairingID: UUID) throws -> Data?
    func all() throws -> [PortholeCredentialRecord]
    func delete(pairingID: UUID) throws
}

/// A failure talking to the system keychain, carrying the raw `OSStatus` so the
/// cause is never swallowed.
public struct PortholeKeychainError: Error, Sendable, Equatable {
    public var status: OSStatus
    public var operation: String

    public init(status: OSStatus, operation: String) {
        self.status = status
        self.operation = operation
    }
}

/// A ``PortholeCredentialStore`` backed by a generic-password keychain item per
/// pairing. The `service` string namespaces the two sides (the device and the
/// Mac client use different services) so they never collide in a shared login
/// keychain.
public struct KeychainCredentialStore: PortholeCredentialStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func save(pairingID: UUID, key: SymmetricKey, metadata: Data) throws {
        try? delete(pairingID: pairingID)
        let keyData = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pairingID.uuidString,
            kSecValueData as String: keyData,
            kSecAttrGeneric as String: metadata,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PortholeKeychainError(status: status, operation: "save")
        }
    }

    public func key(for pairingID: UUID) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pairingID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PortholeKeychainError(status: status, operation: "key")
        }
        return SymmetricKey(data: data)
    }

    public func metadata(for pairingID: UUID) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pairingID.uuidString,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            throw PortholeKeychainError(status: status, operation: "metadata")
        }
        return attributes[kSecAttrGeneric as String] as? Data ?? Data()
    }

    public func all() throws -> [PortholeCredentialRecord] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw PortholeKeychainError(status: status, operation: "all")
        }
        return items.compactMap { attributes in
            guard let account = attributes[kSecAttrAccount as String] as? String,
                  let pairingID = UUID(uuidString: account)
            else { return nil }
            let metadata = attributes[kSecAttrGeneric as String] as? Data ?? Data()
            return PortholeCredentialRecord(pairingID: pairingID, metadata: metadata)
        }
    }

    public func delete(pairingID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pairingID.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PortholeKeychainError(status: status, operation: "delete")
        }
    }
}

#if DEBUG
    /// An in-memory ``PortholeCredentialStore`` for tests and previews — never
    /// ships in release.
    @_spi(Testing)
    public final class InMemoryCredentialStore: PortholeCredentialStore, @unchecked Sendable {
        private struct Entry {
            var key: SymmetricKey
            var metadata: Data
        }

        private let lock = NSLock()
        private var entries: [UUID: Entry] = [:]

        public init() {}

        public func save(pairingID: UUID, key: SymmetricKey, metadata: Data) throws {
            lock.lock()
            defer { lock.unlock() }
            entries[pairingID] = Entry(key: key, metadata: metadata)
        }

        public func key(for pairingID: UUID) throws -> SymmetricKey? {
            lock.lock()
            defer { lock.unlock() }
            return entries[pairingID]?.key
        }

        public func metadata(for pairingID: UUID) throws -> Data? {
            lock.lock()
            defer { lock.unlock() }
            return entries[pairingID]?.metadata
        }

        public func all() throws -> [PortholeCredentialRecord] {
            lock.lock()
            defer { lock.unlock() }
            return entries.map { PortholeCredentialRecord(
                pairingID: $0.key,
                metadata: $0.value.metadata,
            ) }
        }

        public func delete(pairingID: UUID) throws {
            lock.lock()
            defer { lock.unlock() }
            entries[pairingID] = nil
        }
    }
#endif
