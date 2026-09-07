import Foundation
@_spi(Testing) import KeychainKit
import Security
import Testing
@_spi(Testing) @testable import WhereCore

struct BackupRecoveryKeyProviderTests {
    @Test func independentlyCreatedKeysRemainAvailableAfterSynchronization() async throws {
        let shared = InMemoryKeychainCollection()
        let first = BackupRecoveryKeyProvider(
            store: InMemoryKeychainStore(),
            legacyStore: InMemoryKeychainStore(),
            collection: shared,
            isProtectedDataAvailable: { true },
        )
        let second = BackupRecoveryKeyProvider(
            store: InMemoryKeychainStore(),
            legacyStore: InMemoryKeychainStore(),
            collection: shared,
            isProtectedDataAvailable: { true },
        )
        let firstKey = try await first.loadOrCreate()
        let secondKey = try await second.loadOrCreate()
        #expect(firstKey != secondKey)
        #expect(try await first.loadExisting(identifier: secondKey.identifier) == secondKey)
        #expect(try await second.loadExisting(identifier: firstKey.identifier) == firstKey)
        #expect(try await first.loadOrCreate() == firstKey)
        #expect(try await second.loadOrCreate() == secondKey)
    }

    @Test func preservesLegacyKeyWithoutChangingTheSynchronizedItem() async throws {
        let data = Data(repeating: 24, count: 32)
        let legacy = InMemoryKeychainStore(data: data)
        let active = InMemoryKeychainStore()
        let collection = InMemoryKeychainCollection()
        let provider = BackupRecoveryKeyProvider(
            store: active,
            legacyStore: legacy,
            collection: collection,
            isProtectedDataAvailable: { true },
        )
        let key = try await provider.loadOrCreate()
        #expect(key.data == data)
        #expect(try active.read() == data)
        #expect(try legacy.read() == data)
        #expect(collection.read(account: KeychainAccount(key.identifier)) == data)
    }

    private final class SynchronizedCreationRaceStore: KeychainStore, @unchecked Sendable {
        private let lock = NSLock()
        private let winningData: Data
        private var firstRead = true

        init(winningData: Data) {
            self.winningData = winningData
        }

        func read() throws -> Data? {
            lock.withLock {
                if firstRead {
                    firstRead = false
                    return nil
                }
                return winningData
            }
        }

        func create(_: Data) throws {
            throw KeychainError(status: errSecDuplicateItem)
        }

        func write(_: Data) throws {
            Issue.record("The provider must use create-only semantics for a missing key.")
        }

        func remove() throws {}
    }

    @Test func createsAndReusesAStableKeyAfterUnlock() async throws {
        let store = InMemoryKeychainStore()
        let provider = BackupRecoveryKeyProvider(store: store) { true }

        let first = try await provider.loadOrCreate()
        let second = try await provider.loadOrCreate()

        #expect(first == second)
        #expect(Data(base64Encoded: first.base64Encoded)?.count == 32)
    }

    @Test func defersWithoutReadingOrReplacingBeforeFirstUnlock() async {
        let original = Data(repeating: 7, count: 32)
        let store = InMemoryKeychainStore(data: original)
        let provider = BackupRecoveryKeyProvider(store: store) { false }

        await #expect(throws: BackupRecoveryKeyProvider.ProviderError.deferredUntilFirstUnlock) {
            try await provider.loadOrCreate()
        }
        #expect((try? store.read()) == original)
    }

    @Test func interactionNotAllowedDefersWithoutCreatingAReplacement() async {
        let store = InMemoryKeychainStore(
            failure: KeychainError(status: errSecInteractionNotAllowed),
        )
        let provider = BackupRecoveryKeyProvider(store: store) { true }

        await #expect(throws: BackupRecoveryKeyProvider.ProviderError.deferredUntilFirstUnlock) {
            try await provider.loadOrCreate()
        }
    }

    @Test func malformedStoredKeyIsRejected() async {
        let store = InMemoryKeychainStore(data: Data([1, 2, 3]))
        let provider = BackupRecoveryKeyProvider(store: store) { true }

        await #expect(throws: BackupRecoveryKeyProvider.ProviderError.malformedKey) {
            try await provider.loadOrCreate()
        }
    }

    @Test func synchronizedCreationRaceReusesTheWinningKey() async throws {
        let winningData = Data(repeating: 17, count: 32)
        let provider = BackupRecoveryKeyProvider(
            store: SynchronizedCreationRaceStore(winningData: winningData),
        ) { true }

        let key = try await provider.loadOrCreate()
        let expected = try BackupRecoveryKey(data: winningData)

        #expect(key == expected)
    }
}
