import Foundation

/// Deterministic capture metadata. Reference paths remain the source of image identity.
public struct SnapshotManifest: Codable, Equatable, Sendable {
    public static let filename = "snapshot-manifest.json"
    public var version: Int = 1
    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var path: SnapshotPath
        public var testName: String
        public var caseName: String
        public var referenceGroup: String?
        public var configurationIdentifier: String
        public var frame: String
        public var configurationName: String?
        public var layoutTraits: String?
        public var variant: SnapshotVariant

        public init(
            path: SnapshotPath,
            testName: String,
            caseName: String,
            referenceGroup: String?,
            configurationIdentifier: String,
            frame: String,
            configurationName: String?,
            layoutTraits: String?,
            variant: SnapshotVariant,
        ) {
            self.path = path
            self.testName = testName
            self.caseName = caseName
            self.referenceGroup = referenceGroup
            self.configurationIdentifier = configurationIdentifier
            self.frame = frame
            self.configurationName = configurationName
            self.layoutTraits = layoutTraits
            self.variant = variant
        }
    }

    public mutating func upsert(_ entry: Entry) {
        entries.removeAll { $0.path == entry.path }
        entries.append(entry)
        entries.sort { $0.path < $1.path }
    }

    public func validate() throws {
        guard version == 1 else { throw ReviewError.unsupportedVersion(version) }
        guard Set(entries.map(\.path)).count == entries.count
        else { throw ReviewError.invalidDocument("Duplicate manifest paths.") }
    }
}
