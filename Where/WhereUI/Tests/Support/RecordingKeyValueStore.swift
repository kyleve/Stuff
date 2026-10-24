import WhereCore

/// Records preference access while retaining the production-shaped plist round trip.
final class RecordingKeyValueStore: KeyValueStore {
    private let backing = InMemoryKeyValueStore()
    private(set) var readCount = 0
    private(set) var writeCount = 0

    func object(forKey defaultName: String) -> Any? {
        readCount += 1
        return backing.object(forKey: defaultName)
    }

    func bool(forKey defaultName: String) -> Bool {
        readCount += 1
        return backing.bool(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        writeCount += 1
        backing.set(value, forKey: defaultName)
    }

    func removeObject(forKey defaultName: String) {
        writeCount += 1
        backing.removeObject(forKey: defaultName)
    }
}
