import Foundation

/// Device-local evidence shared with the share extension. It never belongs in a backup.
/// The version is a monotonic floor even when access has been withdrawn.
public struct DataCompatibilityReceipt: Codable, Sendable {
    public enum Access: String, Codable, Sendable { case verified, blocked }

    public let accountID: DataCompatibilityAccountID
    public let version: DataModelVersion
    public let access: Access
    public let removedDeviceID: RecordingDeviceID?

    public init(
        accountID: DataCompatibilityAccountID,
        version: DataModelVersion,
        access: Access,
        removedDeviceID: RecordingDeviceID?,
    ) {
        self.accountID = accountID
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

/// Resolves the host-injected group lazily so entitlement/I/O failures reach the gate.
public struct AppGroupDataCompatibilityReceipt: DataCompatibilityReceiptStoring {
    private let appGroupIdentifier: String
    public init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    public func load() throws -> DataCompatibilityReceipt? {
        try FileDataCompatibilityReceipt.shared(appGroupIdentifier: appGroupIdentifier).load()
    }

    public func save(_ receipt: DataCompatibilityReceipt) throws {
        try FileDataCompatibilityReceipt.shared(appGroupIdentifier: appGroupIdentifier)
            .save(receipt)
    }
}

/// Atomic App Group sidecar. Only the app writes; extensions read before opening history.
public struct FileDataCompatibilityReceipt: DataCompatibilityReceiptStoring, Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared(appGroupIdentifier: String) throws -> Self {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        ) else { throw WidgetSnapshotStore.AppGroupUnavailableError() }
        return Self(directory: group.appending(
            path: "DataCompatibility",
            directoryHint: .isDirectory,
        ))
    }

    public func load() throws -> DataCompatibilityReceipt? {
        do {
            let data = try Data(contentsOf: directory.appending(path: "receipt.json"))
            let receipt = try JSONDecoder().decode(DataCompatibilityReceipt.self, from: data)
            guard receipt.version.rawValue > 0, !receipt.accountID.rawValue.isEmpty else {
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
            to: directory.appending(path: "receipt.json"),
            options: .atomic,
        )
    }
}
