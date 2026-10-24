import Foundation
import InstallerKit
import PeriscopeCore

/// Stores InstallerKit's device-local catalog cache outside Throw's user-intent preferences.
public final class UserDefaultsThrowUpdatePreferencesStore: UpdatePreferencesStoring {
    private enum CacheError: Error {
        case invalidStoredType
    }

    private static let storageKey = "Throw.installerUpdates.v1"
    private static let logger = Log<ThrowUpdatePreferencesLog>(system: .shared)

    private let store: any ThrowUpdatePreferencesBackingStore

    public init(userDefaults: UserDefaults) {
        store = userDefaults
    }

    init(store: any ThrowUpdatePreferencesBackingStore) {
        self.store = store
    }

    public var installerUpdates: UpdatePreferences {
        get {
            guard let value = store.object(forKey: Self.storageKey) else {
                return UpdatePreferences(cached: nil)
            }
            guard let data = value as? Data else {
                return discardInvalidCache(CacheError.invalidStoredType)
            }
            do {
                return try JSONDecoder().decode(UpdatePreferences.self, from: data)
            } catch {
                return discardInvalidCache(error)
            }
        }
        set {
            do {
                try store.set(JSONEncoder().encode(newValue), forKey: Self.storageKey)
            } catch {
                Self.logger.cacheWriteFailed(error: .restricted(.errorDetails, error))
            }
        }
    }

    private func discardInvalidCache(_ error: any Error) -> UpdatePreferences {
        Self.logger.cacheRejected(error: .restricted(.errorDetails, error))
        store.removeObject(forKey: Self.storageKey)
        return UpdatePreferences(cached: nil)
    }
}

protocol ThrowUpdatePreferencesBackingStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: ThrowUpdatePreferencesBackingStore {}
