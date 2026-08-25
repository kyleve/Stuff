import Foundation
import Security

public enum AircraftCredentialError: Error, Equatable, Sendable {
    case emptyCredential
    case keychain(status: OSStatus)
    case invalidStoredValue
}

/// A secret whose string/debug descriptions are permanently redacted.
public struct AircraftCredential: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    fileprivate let secret: String

    public init(secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw AircraftCredentialError.emptyCredential
        }
        self.secret = trimmed
    }

    public var lastFour: String? {
        secret.count >= 8 ? String(secret.suffix(4)) : nil
    }

    public var description: String {
        "••••"
    }

    public var debugDescription: String {
        description
    }
}

public enum CredentialState: Equatable, Sendable {
    case missing
    case saved(lastFour: String?)
}

public protocol AircraftCredentialStore: Sendable {
    func state(for id: AircraftCredentialID) async throws -> CredentialState
    func credential(for id: AircraftCredentialID) async throws -> AircraftCredential?
    func save(_ credential: AircraftCredential, for id: AircraftCredentialID) async throws
    func delete(_ id: AircraftCredentialID) async throws
}

/// Stores each provider credential as a generic-password item that is only
/// available while the device is unlocked and never migrates to another device.
public actor KeychainAircraftCredentialStore: AircraftCredentialStore {
    private let service: String
    private let accountPrefix: String

    public init(service: String, accountPrefix: String) {
        precondition(service.isEmpty == false)
        precondition(accountPrefix.isEmpty == false)
        self.service = service
        self.accountPrefix = accountPrefix
    }

    public func state(for id: AircraftCredentialID) throws -> CredentialState {
        guard let credential = try credential(for: id) else { return .missing }
        return .saved(lastFour: credential.lastFour)
    }

    public func credential(for id: AircraftCredentialID) throws -> AircraftCredential? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                guard let data = item as? Data,
                      let value = String(data: data, encoding: .utf8)
                else {
                    throw AircraftCredentialError.invalidStoredValue
                }
                return try AircraftCredential(secret: value)
            case errSecItemNotFound:
                return nil
            default:
                throw AircraftCredentialError.keychain(status: status)
        }
    }

    public func save(_ credential: AircraftCredential, for id: AircraftCredentialID) throws {
        let valueData = Data(credential.secret.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let query = baseQuery(for: id)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var addition = query
                addition.merge(attributes) { _, new in new }
                let addStatus = SecItemAdd(addition as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw AircraftCredentialError.keychain(status: addStatus)
                }
            default:
                throw AircraftCredentialError.keychain(status: updateStatus)
        }
    }

    public func delete(_ id: AircraftCredentialID) throws {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AircraftCredentialError.keychain(status: status)
        }
    }

    private func baseQuery(for id: AircraftCredentialID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(accountPrefix).\(id.rawValue)",
        ]
    }
}

public actor MemoryAircraftCredentialStore: AircraftCredentialStore {
    private var credentials: [AircraftCredentialID: AircraftCredential]

    public init(credentials: [AircraftCredentialID: AircraftCredential]) {
        self.credentials = credentials
    }

    public func state(for id: AircraftCredentialID) -> CredentialState {
        guard let credential = credentials[id] else { return .missing }
        return .saved(lastFour: credential.lastFour)
    }

    public func credential(for id: AircraftCredentialID) -> AircraftCredential? {
        credentials[id]
    }

    public func save(_ credential: AircraftCredential, for id: AircraftCredentialID) {
        credentials[id] = credential
    }

    public func delete(_ id: AircraftCredentialID) {
        credentials[id] = nil
    }
}

extension AircraftCredential {
    var authenticationHeaderValue: String {
        secret
    }
}
