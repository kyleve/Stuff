import CryptoKit
import Foundation
@_spi(Testing) import PortholeCore
import Testing

struct PortholeCredentialStoreTests {
    @Test func savesAndReadsBackKeyAndMetadata() throws {
        let store = InMemoryCredentialStore()
        let id = UUID()
        let key = SymmetricKey(size: .bits256)
        let metadata = Data("device-name".utf8)

        try store.save(pairingID: id, key: key, metadata: metadata)
        #expect(try store.key(for: id) == key)
        #expect(try store.metadata(for: id) == metadata)
    }

    @Test func listsAllRecordsWithoutSecrets() throws {
        let store = InMemoryCredentialStore()
        let first = UUID()
        let second = UUID()
        try store.save(
            pairingID: first,
            key: SymmetricKey(size: .bits256),
            metadata: Data("a".utf8),
        )
        try store.save(
            pairingID: second,
            key: SymmetricKey(size: .bits256),
            metadata: Data("b".utf8),
        )

        let records = try store.all()
            .sorted {
                $0.metadata.count < $1.metadata.count || $0.pairingID.uuidString < $1.pairingID
                    .uuidString
            }
        #expect(Set(records.map(\.pairingID)) == [first, second])
        #expect(Set(records.map(\.metadata)) == [Data("a".utf8), Data("b".utf8)])
    }

    @Test func deleteRemovesTheEntry() throws {
        let store = InMemoryCredentialStore()
        let id = UUID()
        try store.save(pairingID: id, key: SymmetricKey(size: .bits256), metadata: Data())
        try store.delete(pairingID: id)
        #expect(try store.key(for: id) == nil)
        #expect(try store.all().isEmpty)
    }

    @Test func missingKeyReturnsNil() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.key(for: UUID()) == nil)
        #expect(try store.metadata(for: UUID()) == nil)
    }
}
