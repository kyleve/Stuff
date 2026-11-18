import Foundation
@testable import StorageKit
import Testing

struct KeyValueStoreTests {
    @Test
    func inMemoryRoundTripsEachType() {
        let store = InMemoryKeyValueStore()
        store.set(true, forKey: "flag")
        store.set(42, forKey: "count")
        store.set(3.5, forKey: "ratio")
        store.set("hi", forKey: "label")
        store.set(Data([1, 2, 3]), forKey: "blob")

        #expect(store.bool(forKey: "flag"))
        #expect(store.integer(forKey: "count") == 42)
        #expect(store.double(forKey: "ratio") == 3.5)
        #expect(store.string(forKey: "label") == "hi")
        #expect(store.data(forKey: "blob") == Data([1, 2, 3]))
    }

    @Test
    func inMemoryReturnsDefaultsForAbsentKeys() {
        let store = InMemoryKeyValueStore()
        #expect(!store.bool(forKey: "missing"))
        #expect(store.integer(forKey: "missing") == 0)
        #expect(store.double(forKey: "missing") == 0)
        #expect(store.string(forKey: "missing") == nil)
        #expect(store.data(forKey: "missing") == nil)
    }

    @Test
    func inMemoryReadingTheWrongTypeReturnsTheDefault() {
        let store = InMemoryKeyValueStore()
        store.set(true, forKey: "flag")
        #expect(store.integer(forKey: "flag") == 0)
        #expect(store.string(forKey: "flag") == nil)
    }

    @Test
    func inMemorySettingNilOrRemovingClearsTheKey() {
        let store = InMemoryKeyValueStore()
        store.set("hi", forKey: "label")
        store.set(nil as String?, forKey: "label")
        #expect(store.string(forKey: "label") == nil)

        store.set(Data([9]), forKey: "blob")
        store.removeObject(forKey: "blob")
        #expect(store.data(forKey: "blob") == nil)
    }

    @Test
    func userDefaultsWrapperRoundTripsAndRemoves() throws {
        let suiteName = "StorageKitTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsKeyValueStore(suite)

        store.set(7, forKey: "count")
        store.set("hi", forKey: "label")
        #expect(store.integer(forKey: "count") == 7)
        #expect(store.string(forKey: "label") == "hi")

        store.set(nil as String?, forKey: "label")
        #expect(store.string(forKey: "label") == nil)
    }
}
