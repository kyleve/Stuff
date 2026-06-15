import Foundation

/// The slice of `UserDefaults` the app persists preferences through, abstracted
/// so production can use a real defaults suite while tests use an in-memory
/// double. Only the methods `WherePreferences` needs are declared, and
/// `UserDefaults` already satisfies them.
public protocol KeyValueStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}
