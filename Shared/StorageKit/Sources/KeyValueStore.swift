import Foundation

/// A minimal, `Sendable`-clean key-value store: typed accessors only (no
/// `Any?`), so a value can't silently fail to round-trip the way an arbitrary
/// `set(_: Any?)` can. `StorageContainer.keyValue.store()` vends a namespaced one
/// per node — a real `UserDefaults` suite in `.persistent` mode, an in-memory
/// dictionary in `.inMemory` mode — behind this same protocol, so app code
/// doesn't know or care which it got.
///
/// Reads of an absent key mirror `UserDefaults`: `bool` → `false`,
/// `integer`/`double` → `0`, `string`/`data` → `nil`.
public protocol KeyValueStore: AnyObject, Sendable {
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func double(forKey key: String) -> Double
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?

    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func set(_ value: String?, forKey key: String)
    func set(_ value: Data?, forKey key: String)

    func removeObject(forKey key: String)
}

/// `KeyValueStore` backed by a `UserDefaults` suite. `UserDefaults` is internally
/// thread-safe, so wrapping it as `@unchecked Sendable` is sound. Setting a `nil`
/// `String`/`Data` removes the key, matching the in-memory store.
final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func integer(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    func double(forKey key: String) -> Double {
        defaults.double(forKey: key)
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func set(_ value: Data?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory `KeyValueStore` used in `.inMemory` mode (and handy for tests).
/// Lock-guarded so it is safely `Sendable`, with one typed slot per key so a
/// value read back as the wrong type reads as absent rather than crashing.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private enum Value {
        case bool(Bool)
        case integer(Int)
        case double(Double)
        case string(String)
        case data(Data)
    }

    private let lock = NSLock()
    private var storage: [String: Value] = [:]

    public init() {}

    private func value(forKey key: String) -> Value? {
        lock.withLock { storage[key] }
    }

    private func store(_ value: Value?, forKey key: String) {
        lock.withLock { storage[key] = value }
    }

    public func bool(forKey key: String) -> Bool {
        if case let .bool(value) = value(forKey: key) { return value }
        return false
    }

    public func integer(forKey key: String) -> Int {
        if case let .integer(value) = value(forKey: key) { return value }
        return 0
    }

    public func double(forKey key: String) -> Double {
        if case let .double(value) = value(forKey: key) { return value }
        return 0
    }

    public func string(forKey key: String) -> String? {
        if case let .string(value) = value(forKey: key) { return value }
        return nil
    }

    public func data(forKey key: String) -> Data? {
        if case let .data(value) = value(forKey: key) { return value }
        return nil
    }

    public func set(_ value: Bool, forKey key: String) {
        store(.bool(value), forKey: key)
    }

    public func set(_ value: Int, forKey key: String) {
        store(.integer(value), forKey: key)
    }

    public func set(_ value: Double, forKey key: String) {
        store(.double(value), forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        store(value.map(Value.string), forKey: key)
    }

    public func set(_ value: Data?, forKey key: String) {
        store(value.map(Value.data), forKey: key)
    }

    public func removeObject(forKey key: String) {
        store(nil, forKey: key)
    }
}
