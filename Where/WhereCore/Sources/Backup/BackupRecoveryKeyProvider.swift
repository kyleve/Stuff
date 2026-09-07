import CryptoKit
import Foundation
import KeychainKit
import Security

/// The 256-bit secret used to encrypt automatic backups. Its Base64 form is
/// the recovery value shown to the user; callers must never log either form.
public struct BackupRecoveryKey: Hashable, Sendable {
    public static let byteCount = 32

    let data: Data

    public init(base64Encoded value: String) throws {
        guard let data = Data(base64Encoded: value), data.count == Self.byteCount else {
            throw BackupRecoveryKeyProvider.ProviderError.malformedKey
        }
        self.data = data
    }

    init(data: Data) throws {
        guard data.count == Self.byteCount else {
            throw BackupRecoveryKeyProvider.ProviderError.malformedKey
        }
        self.data = data
    }

    public var base64Encoded: String {
        data.base64EncodedString()
    }

    public var identifier: String {
        Data(SHA256.hash(data: data).prefix(12))
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    var symmetricKey: SymmetricKey {
        SymmetricKey(data: data)
    }
}

/// Loads the synchronized automatic-backup key, creating it only after the
/// device has exposed protected data and Keychain explicitly reports absence.
public actor BackupRecoveryKeyProvider {
    public enum ProviderError: Error, LocalizedError, Equatable {
        case deferredUntilFirstUnlock
        case malformedKey
        case keychain(KeychainError)

        public var errorDescription: String? {
            switch self {
                case .deferredUntilFirstUnlock:
                    "The backup key is unavailable until this device is unlocked."
                case .malformedKey:
                    "The backup recovery key is not valid."
                case let .keychain(error):
                    error.localizedDescription
            }
        }
    }

    public static let service = "com.stuff.where"
    public static let account = "automatic-backup-recovery-key-v1"

    private let store: any KeychainStore
    private let isProtectedDataAvailable: @Sendable () async -> Bool

    public init(
        store: any KeychainStore,
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool,
    ) {
        self.store = store
        self.isProtectedDataAvailable = isProtectedDataAvailable
    }

    public static func system(
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool,
    ) -> BackupRecoveryKeyProvider {
        BackupRecoveryKeyProvider(
            store: SystemKeychainStore(
                service: service,
                account: account,
                accessibility: .afterFirstUnlock,
                synchronizesThroughICloud: true,
            ),
            isProtectedDataAvailable: isProtectedDataAvailable,
        )
    }

    public func loadOrCreate() async throws -> BackupRecoveryKey {
        guard await isProtectedDataAvailable() else {
            throw ProviderError.deferredUntilFirstUnlock
        }

        do {
            if let existing = try store.read() {
                return try BackupRecoveryKey(data: existing)
            }

            let created = try BackupRecoveryKey(
                data: Data((0 ..< BackupRecoveryKey.byteCount).map { _ in
                    UInt8.random(in: .min ... .max)
                }),
            )
            do {
                try store.create(created.data)
                return created
            } catch let error as KeychainError where error.status == errSecDuplicateItem {
                // Another synchronized writer won the creation race. The
                // winner is authoritative; never overwrite it with ours.
                guard let winner = try store.read() else {
                    throw ProviderError.keychain(error)
                }
                return try BackupRecoveryKey(data: winner)
            }
        } catch let error as ProviderError {
            throw error
        } catch let error as KeychainError where error.isInteractionNotAllowed {
            throw ProviderError.deferredUntilFirstUnlock
        } catch let error as KeychainError {
            throw ProviderError.keychain(error)
        }
    }

    /// Loads an existing key without minting one. Restore uses this before it
    /// asks the user for the copied recovery key.
    public func loadExisting() async throws -> BackupRecoveryKey? {
        guard await isProtectedDataAvailable() else {
            throw ProviderError.deferredUntilFirstUnlock
        }
        do {
            guard let data = try store.read() else { return nil }
            return try BackupRecoveryKey(data: data)
        } catch let error as ProviderError {
            throw error
        } catch let error as KeychainError where error.isInteractionNotAllowed {
            throw ProviderError.deferredUntilFirstUnlock
        } catch let error as KeychainError {
            throw ProviderError.keychain(error)
        }
    }
}
