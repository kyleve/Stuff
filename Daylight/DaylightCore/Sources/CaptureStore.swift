import Foundation

/// One injected owner for atomic metadata and durable image staging. Never deletes Photos assets.
public actor CaptureStore {
    private let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private struct Envelope<T: Codable>: Codable { let version: Int; let value: T }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func saveSettings(_ settings: CaptureSettings) throws {
        try settings.validate()
        try write(settings, to: root.appendingPathComponent("settings.json"))
    }

    public func settings() throws -> CaptureSettings {
        let url = root.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .standard }
        let value: CaptureSettings = try read(url)
        try value.validate()
        return value
    }

    public func save(_ sequence: CaptureSequence) throws {
        try write(
            sequence,
            to: root.appendingPathComponent("sequence-\(sequence.id.storageKey).json"),
        )
    }

    public func sequences() throws -> [CaptureSequence] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sequence-") && $0.pathExtension == "json" }
            .map { try read($0) as CaptureSequence }.sorted { $0.event.date > $1.event.date }
    }

    public enum Resource: String, Sendable { case original, rendered }
    public func imageURL(_ imageID: CaptureSequence.Slot.ID, resource: Resource) -> URL {
        root.appendingPathComponent("\(imageID.rawValue.uuidString)-\(resource.rawValue).jpg")
    }

    public func stage(_ data: Data, imageID: CaptureSequence.Slot.ID, resource: Resource) throws {
        let values = try root
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < max(
            200_000_000,
            Int64(data.count) * 4,
        ) {
            throw DaylightError.insufficientStorage
        }
        try data.write(to: imageURL(imageID, resource: resource), options: .atomic)
    }

    public func removeStagedFiles(imageID: CaptureSequence.Slot.ID) throws {
        for resource in [Resource.original, .rendered] {
            let url = imageURL(imageID, resource: resource)
            if FileManager.default
                .fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private func write(_ value: some Codable, to url: URL) throws {
        try encoder.encode(Envelope(version: 1, value: value)).write(to: url, options: .atomic)
    }

    private func read<T: Codable>(_ url: URL) throws -> T {
        let envelope = try decoder.decode(Envelope<T>.self, from: Data(contentsOf: url))
        guard envelope.version == 1 else { throw DaylightError.unsupportedVersion }
        return envelope.value
    }
}
