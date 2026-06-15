import Foundation
import WhereCore

/// An in-memory `KeyValueStore` for tests: no suite, no disk, nothing to leak
/// or clean up (unlike a `UserDefaults(suiteName:)` that has to be torn down).
///
/// Each `set` round-trips the value through a binary property list, so a value
/// that wouldn't survive `UserDefaults`' on-disk persistence fails here too —
/// the round-trip guarantee a plain in-memory dictionary wouldn't give.
public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Any] = [:]

    public init() {}

    public func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    public func bool(forKey defaultName: String) -> Bool {
        switch storage[defaultName] {
            case let value as Bool: value
            case let value as NSNumber: value.boolValue
            default: false
        }
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        guard let value else {
            storage[defaultName] = nil
            return
        }
        storage[defaultName] = Self.roundTripped(value)
    }

    public func removeObject(forKey defaultName: String) {
        storage[defaultName] = nil
    }

    /// Serialize then deserialize through a binary plist so only values that
    /// `UserDefaults` could actually persist survive; a non-serializable value
    /// traps here exactly as it would corrupt on-disk defaults.
    private static func roundTripped(_ value: Any) -> Any {
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["value": value],
                format: .binary,
                options: 0,
            )
            let decoded = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil,
            )
            guard
                let wrapper = decoded as? [String: Any],
                let restored = wrapper["value"]
            else {
                fatalError("Round-tripped plist lost its wrapped value")
            }
            return restored
        } catch {
            fatalError("Value for in-memory defaults is not property-list serializable: \(error)")
        }
    }
}
