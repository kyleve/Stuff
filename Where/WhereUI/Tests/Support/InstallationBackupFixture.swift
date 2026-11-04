import Foundation
import Testing
import WhereCore

/// Models an atomic platform backup of a quiescent installation. It follows the actual URL
/// backup-exclusion attributes; the caller owns a separate device-only Keychain resource.
struct InstallationBackupFixture {
    let directory: URL

    static func capture(_ root: URL) throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "installation-backup-\(UUID())")
        try copyIncluded(root, to: directory)
        return Self(directory: directory)
    }

    func restore(to root: URL) throws {
        try Self.copyIncluded(directory, to: root)
    }

    func cleanup() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record(error) }
    }

    private static func copyIncluded(_ source: URL, to destination: URL) throws {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        guard values.isExcludedFromBackup != true else { return }
        if values.isDirectory == true {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true,
            )
            for child in try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
            ) {
                try copyIncluded(child, to: destination.appending(path: child.lastPathComponent))
            }
        } else {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }
}

/// Backs WherePreferences with the same property-list boundary as UserDefaults. The fixture
/// flushes before a quiescent backup; neither the Keychain nor local sidecars are stored here.
final class InstallationPreferencesFixture: KeyValueStore {
    private var values: [String: Any]
    let file: URL
    init(file: URL) throws {
        self.file = file
        do {
            let data = try Data(contentsOf: file)
            guard let decoded = try PropertyListSerialization.propertyList(
                from: data,
                format: nil,
            ) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            values = decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { values = [:] }
    }

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func bool(forKey key: String) -> Bool {
        (values[key] as? NSNumber)?.boolValue ?? false
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func flush() throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            .write(
                to: file,
                options: .atomic,
            )
    }
}
