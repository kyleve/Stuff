import CryptoKit
import Foundation
import StuffCore

/// AES-GCM encryption for every sensitive payload written outside the Keychain.
public struct VaultCipher: Sendable {
    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == 32 else {
            throw PatchlightVaultError.invalidKey
        }
        key = SymmetricKey(data: keyData)
    }

    public func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw PatchlightVaultError.encryptionFailed
        }
        return combined
    }

    public func open(_ ciphertext: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw PatchlightVaultError.authenticationFailed
        }
    }
}

public enum PatchlightVaultError: LocalizedError, Equatable, Sendable {
    case invalidKey
    case encryptionFailed
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
            case .invalidKey:
                "Patchlight's vault key is invalid."
            case .encryptionFailed:
                "Patchlight could not encrypt the local payload."
            case .authenticationFailed:
                "Patchlight could not authenticate the encrypted local payload."
        }
    }
}

/// Creates and removes only the account vault key; provider credentials use
/// separate app-global keys and therefore survive GitHub sign-out.
struct AccountVaultKeyManager {
    private let accountID: PatchlightAccountID
    private let credentialStore: any CredentialStore

    init(accountID: PatchlightAccountID, credentialStore: any CredentialStore) {
        self.accountID = accountID
        self.credentialStore = credentialStore
    }

    func loadOrCreate() throws -> Data {
        if let existing = try credentialStore.data(for: credentialKey) {
            guard existing.count == 32 else { throw PatchlightVaultError.invalidKey }
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try credentialStore.set(data, for: credentialKey)
        return data
    }

    func remove() throws {
        try credentialStore.remove(credentialKey)
    }

    private var credentialKey: CredentialKey {
        CredentialKey("account.\(accountID.rawValue).vault-key")
    }
}
