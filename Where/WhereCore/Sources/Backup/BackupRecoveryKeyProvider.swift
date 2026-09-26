import CryptoKit
import Foundation
@_spi(Testing) import KeychainKit
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

/// Pins this installation's active secret locally and preserves each secret
/// under its own synchronized account. No synchronized secret is overwritten.
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
    private let legacyStore: any KeychainStore
    private let collection: any KeychainCollection
    private let isProtectedDataAvailable: @Sendable () async -> Bool

    public init(
        store: any KeychainStore,
        legacyStore: any KeychainStore,
        collection: any KeychainCollection,
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool,
    ) {
        self.store = store
        self.legacyStore = legacyStore
        self.collection = collection
        self.isProtectedDataAvailable = isProtectedDataAvailable
    }

    @_spi(Testing)
    public init(
        store: any KeychainStore,
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool,
    ) {
        self.store = store
        legacyStore = InMemoryKeychainStore()
        collection = InMemoryKeychainCollection()
        self.isProtectedDataAvailable = isProtectedDataAvailable
    }

    public static func system(
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool,
    ) -> BackupRecoveryKeyProvider {
        BackupRecoveryKeyProvider(
            store: SystemKeychainStore(
                service: service,
                account: "automatic-backup-active-key-v2",
                accessibility: .afterFirstUnlock,
                synchronizesThroughICloud: false,
            ),
            legacyStore: SystemKeychainStore(
                service: service,
                account: account,
                accessibility: .afterFirstUnlock,
                synchronizesThroughICloud: true,
            ),
            collection: SystemKeychainCollection(
                service: "com.stuff.where.automatic-backup-keys-v2",
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
        try Task.checkCancellation()

        do {
            let legacy = try legacyStore.read()
            if let legacy { try preserve(BackupRecoveryKey(data: legacy)) }
            if let existing = try store.read() {
                let key = try BackupRecoveryKey(data: existing)
                try preserve(key)
                return key
            }

            let created = try BackupRecoveryKey(
                data: legacy ?? Data((0 ..< BackupRecoveryKey.byteCount).map { _ in
                    UInt8.random(in: .min ... .max)
                }),
            )
            // Preserve before pinning or exporting. Two offline installations
            // create different accounts, so later synchronization retains both.
            try preserve(created)
            do {
                try store.create(created.data)
                return created
            } catch let error as KeychainError where error.status == errSecDuplicateItem {
                // Only the local pin can race. Both candidates remain in the
                // synchronized collection, including the losing candidate.
                guard let winner = try store.read() else {
                    throw ProviderError.keychain(error)
                }
                let key = try BackupRecoveryKey(data: winner)
                try preserve(key)
                return key
            }
        } catch let error as ProviderError {
            throw error
        } catch let error as KeychainError where error.isInteractionNotAllowed {
            throw ProviderError.deferredUntilFirstUnlock
        } catch let error as KeychainError {
            throw ProviderError.keychain(error)
        }
    }

    private func preserve(_ key: BackupRecoveryKey) throws {
        let account = KeychainAccount(key.identifier)
        do {
            try collection.create(key.data, account: account)
        } catch let error as KeychainError where error.status == errSecDuplicateItem {
            guard try collection.read(account: account) == key.data else {
                throw ProviderError.malformedKey
            }
        }
    }

    /// Resolve the envelope's exact key, including keys created on another
    /// installation. A user-entered key never goes through this write path.
    public func loadExisting(identifier: String) async throws -> BackupRecoveryKey? {
        guard await isProtectedDataAvailable() else {
            throw ProviderError.deferredUntilFirstUnlock
        }
        do {
            if let data = try collection.read(account: KeychainAccount(identifier)) {
                let key = try BackupRecoveryKey(data: data)
                guard key.identifier == identifier else { throw ProviderError.malformedKey }
                return key
            }
            for candidate in try [store.read(), legacyStore.read()] {
                if let candidate {
                    let key = try BackupRecoveryKey(data: candidate)
                    if key.identifier == identifier {
                        try preserve(key)
                        return key
                    }
                }
            }
            return nil
        } catch let error as KeychainError where error.isInteractionNotAllowed {
            throw ProviderError.deferredUntilFirstUnlock
        } catch let error as KeychainError {
            throw ProviderError.keychain(error)
        }
    }
}
