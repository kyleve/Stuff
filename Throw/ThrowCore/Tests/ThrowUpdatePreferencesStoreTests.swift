import Foundation
import InstallerKit
import Testing
@testable import ThrowCore

struct ThrowUpdatePreferencesStoreTests {
    @Test func missingValueStartsEmpty() {
        let preferences = UserDefaultsThrowUpdatePreferencesStore(
            store: MemoryThrowUpdatePreferencesBackingStore(),
        )

        #expect(preferences.installerUpdates == UpdatePreferences(cached: nil))
    }

    @Test func cacheRoundTrips() throws {
        let store = MemoryThrowUpdatePreferencesBackingStore()
        let preferences = UserDefaultsThrowUpdatePreferencesStore(store: store)
        let value = try updatePreferences()

        preferences.installerUpdates = value

        #expect(
            UserDefaultsThrowUpdatePreferencesStore(store: store).installerUpdates == value,
        )
    }

    @Test func corruptValuesAreDiscarded() {
        for value: Any in ["not data", Data("not JSON".utf8)] {
            let store = MemoryThrowUpdatePreferencesBackingStore(value: value)
            let preferences = UserDefaultsThrowUpdatePreferencesStore(store: store)

            #expect(preferences.installerUpdates == UpdatePreferences(cached: nil))
            #expect(store.value == nil)
        }
    }

    private func updatePreferences() throws -> UpdatePreferences {
        let catalog = try JSONDecoder().decode(
            UpdateCatalog.self,
            from: Data(#"{"schemaVersion":3,"apps":[]}"#.utf8),
        )
        return try UpdatePreferences(cached: .init(
            feedURL: #require(URL(string: "https://example.org/updates.json")),
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
            catalog: catalog,
        ))
    }
}

private final class MemoryThrowUpdatePreferencesBackingStore:
    ThrowUpdatePreferencesBackingStore
{
    var value: Any?

    init(value: Any? = nil) {
        self.value = value
    }

    func object(forKey _: String) -> Any? {
        value
    }

    func set(_ value: Any?, forKey _: String) {
        self.value = value
    }

    func removeObject(forKey _: String) {
        value = nil
    }
}
