import Foundation
import SwiftData

/// Records, in shared `UserDefaults`, the schema version the store was last
/// opened with, so the launch flow can *predict* a migration before opening
/// the `ModelContainer`.
///
/// SwiftData exposes no pre-open "what version is on disk" API and no migration
/// progress callback, so this marker is how the launch sequence decides whether
/// to arm the migration UI: if the recorded version is behind the current
/// schema, a migration will (likely) run when the container opens.
public struct SchemaVersionMarker {
    private static let appGroupIdentifier = "group.com.stuff.where"

    private let defaults: UserDefaults
    private let key: String
    private let currentVersion: Schema.Version

    public init(
        defaults: UserDefaults,
        currentVersion: Schema.Version,
        key: String = "where.schemaVersion",
    ) {
        self.defaults = defaults
        self.key = key
        self.currentVersion = currentVersion
    }

    /// Production marker: shared app-group defaults, current bundle schema.
    public static var standard: SchemaVersionMarker {
        SchemaVersionMarker(
            defaults: UserDefaults(suiteName: appGroupIdentifier) ?? .standard,
            currentVersion: WhereCurrentSchema.versionIdentifier,
        )
    }

    /// The version the store was last opened with, or nil if never recorded
    /// (a fresh install).
    public var recordedVersion: Schema.Version? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return Self.version(from: raw)
    }

    /// True when a version was previously recorded and is older than the
    /// current schema — i.e. opening the store will (likely) migrate. A fresh
    /// install (nothing recorded) is not a migration.
    public var migrationExpected: Bool {
        guard let recordedVersion else { return false }
        return recordedVersion < currentVersion
    }

    /// Persist the current schema version. Call after a successful open so the
    /// next launch compares against an up-to-date marker.
    public func recordCurrentVersion() {
        defaults.set(Self.string(from: currentVersion), forKey: key)
    }

    private static func string(from version: Schema.Version) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    private static func version(from string: String) -> Schema.Version? {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Schema.Version(parts[0], parts[1], parts[2])
    }
}
