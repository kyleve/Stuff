import Foundation

/// Device-local evidence shared with the share extension. It never belongs in a backup.
/// The version is a monotonic floor even when access has been withdrawn.
public struct DataCompatibilityReceipt: Codable, Equatable, Sendable {
    public enum Access: String, Codable, Equatable, Sendable { case verified, blocked }

    public let domain: DataCompatibilityDomain
    public let version: DataModelVersion
    public let access: Access
    public let removedDeviceID: RecordingDeviceID?

    public init(
        domain: DataCompatibilityDomain,
        version: DataModelVersion,
        access: Access,
        removedDeviceID: RecordingDeviceID?,
    ) {
        self.domain = domain
        self.version = version
        self.access = access
        self.removedDeviceID = removedDeviceID
    }

    public func requireAccess(version: DataModelVersion) throws {
        guard self.version == version, access == .verified else {
            throw DataCompatibilityFailure.recordingDeviceRequired
        }
    }
}

@MainActor
public protocol DataCompatibilityReceiptStoring {
    func load() throws -> DataCompatibilityReceipt?
    func save(_ receipt: DataCompatibilityReceipt) throws
}

/// Atomic App Group sidecar. Only the app writes; extensions read before opening history.
public nonisolated struct FileDataCompatibilityReceipt: DataCompatibilityReceiptStoring, Sendable {
    private static let directoryName = "DataCompatibility"
    private static let fileName = "receipt.json"
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared(appGroupIdentifier: String) throws -> Self {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        ) else { throw WidgetSnapshotStore.AppGroupUnavailableError() }
        return inAppGroup(directory: group)
    }

    static func inAppGroup(directory: URL) -> Self {
        Self(directory: directory.appending(path: directoryName, directoryHint: .isDirectory))
    }

    public func load() throws -> DataCompatibilityReceipt? {
        do {
            let data = try Data(contentsOf: directory.appending(path: Self.fileName))
            let receipt = try JSONDecoder().decode(DataCompatibilityReceipt.self, from: data)
            guard receipt.version.rawValue > 0, receipt.domain.isValid else {
                throw DataCompatibilityTransportError.invalidRecord
            }
            return receipt
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func save(_ receipt: DataCompatibilityReceipt) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try url.setResourceValues(attributes)
        try JSONEncoder().encode(receipt).write(
            to: directory.appending(path: Self.fileName),
            options: .atomic,
        )
    }
}
