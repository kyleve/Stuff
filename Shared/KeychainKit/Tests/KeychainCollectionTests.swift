import Foundation
@_spi(Testing) import KeychainKit
import Security
import Testing

struct KeychainCollectionTests {
    @Test func preservesIndependentAccountsAndRejectsReplacement() throws {
        let store = InMemoryKeychainCollection()
        let first = KeychainAccount("first")
        let second = KeychainAccount("second")
        #expect(store.read(account: first) == nil)
        try store.create(Data([1]), account: first)
        try store.create(Data([2]), account: second)
        #expect(throws: KeychainError(status: errSecDuplicateItem)) {
            try store.create(Data([3]), account: first)
        }
        #expect(store.read(account: first) == Data([1]))
        #expect(store.read(account: second) == Data([2]))
    }
}
