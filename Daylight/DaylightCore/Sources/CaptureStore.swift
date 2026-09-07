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

    public func armedIntent() throws -> Bool {
        let url = root.appendingPathComponent("armed.json")
        return FileManager.default.fileExists(atPath: url.path) ? try read(url) : false
    }

    public func setArmedIntent(_ armed: Bool) throws {
        try write(
            armed,
            to: root.appendingPathComponent("armed.json"),
        )
    }

    public func saveManual(_ record: ManualCapture) throws {
        try write(
            record,
            to: root.appendingPathComponent("manual-\(record.id.rawValue.uuidString).json"),
        )
    }

    public func manualCaptures() throws -> [ManualCapture] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("manual-") && $0.pathExtension == "json" }
            .map { try read($0) as ManualCapture }.sorted { $0.date > $1.date }
    }

    #if DEBUG
        private var capacityOverride: Int64?
        @_spi(Testing) public func overrideAvailableCapacity(_ bytes: Int64) {
            capacityOverride = bytes
        }
    #endif

    private func availableCapacity() throws -> Int64? {
        #if DEBUG
            if let capacityOverride { return capacityOverride }
        #endif
        return try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    public func requireAvailableSpace() throws {
        if let available = try availableCapacity(),
           available < 200_000_000
        {
            throw DaylightError.insufficientStorage
        }
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

    public enum Resource: String, Sendable { case original, raw }
    public func imageURL(_ imageID: CaptureSequence.Slot.ID, resource: Resource) -> URL {
        let extensionName = resource == .raw ? "dng" : "jpg"
        return root
            .appendingPathComponent(
                "\(imageID.rawValue.uuidString)-\(resource.rawValue).\(extensionName)",
            )
    }

    public func stageCapture(_ capture: CameraCapture, imageID: CaptureSequence.Slot.ID) throws {
        // Stage RAW first; a JPEG's presence marks the complete pair for crash recovery.
        if let raw = capture.raw { try stage(raw, imageID: imageID, resource: .raw) }
        try stage(capture.jpeg, imageID: imageID, resource: .original)
    }

    public func rawURL(_ imageID: CaptureSequence.Slot.ID) -> URL? {
        let url = imageURL(imageID, resource: .raw)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func stage(_ data: Data, imageID: CaptureSequence.Slot.ID, resource: Resource) throws {
        if let available = try availableCapacity(), available < max(
            200_000_000,
            Int64(data.count) * 4,
        ) {
            throw DaylightError.insufficientStorage
        }
        try data.write(to: imageURL(imageID, resource: resource), options: .atomic)
    }

    public func removeStagedFiles(imageID: CaptureSequence.Slot.ID) throws {
        let receipt = imageURL(imageID, resource: .original).deletingPathExtension()
            .appendingPathExtension("photos-receipt")
        if FileManager.default
            .fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
        for resource in [Resource.original, .raw] {
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
