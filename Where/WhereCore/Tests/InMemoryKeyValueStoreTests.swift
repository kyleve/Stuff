import Foundation
import Testing
@_spi(Testing) import WhereCore

/// Covers `InMemoryKeyValueStore`'s round-trip fidelity: it stores/reads values
/// like `UserDefaults` and, crucially, forces each value through a binary plist
/// so a non-persistable value fails in tests exactly as it would corrupt on-disk
/// defaults.
struct InMemoryKeyValueStoreTests {
    @Test func storesAndReadsBackValues() {
        let store = InMemoryKeyValueStore()
        store.set("hello", forKey: "greeting")
        store.set(42, forKey: "answer")

        #expect(store.object(forKey: "greeting") as? String == "hello")
        #expect(store.object(forKey: "answer") as? Int == 42)
    }

    @Test func boolReadsCoerceNumbers() {
        let store = InMemoryKeyValueStore()
        store.set(true, forKey: "flag")

        #expect(store.bool(forKey: "flag"))
        #expect(store.bool(forKey: "missing") == false)
    }

    @Test func removeAndNilClearTheValue() {
        let store = InMemoryKeyValueStore()
        store.set("x", forKey: "key")
        store.removeObject(forKey: "key")
        #expect(store.object(forKey: "key") == nil)

        store.set("y", forKey: "key")
        store.set(nil, forKey: "key")
        #expect(store.object(forKey: "key") == nil)
    }

    @Test func setRoundTripsThroughAPropertyList() {
        let store = InMemoryKeyValueStore()
        let date = Date(timeIntervalSince1970: 1_000_000)
        store.set(["nested": [1, 2, 3], "when": date], forKey: "compound")

        let restored = store.object(forKey: "compound") as? [String: Any]
        #expect(restored?["nested"] as? [Int] == [1, 2, 3])
        #expect(restored?["when"] as? Date == date)
    }
}
