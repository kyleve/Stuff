import Foundation

public struct AutomaticBackupFile: Identifiable, Hashable, Sendable {
    public enum StorageLocation: String, Codable, Hashable, Sendable {
        case iCloudDrive
        case appDocuments
    }

    public enum Protection: String, Codable, Hashable, Sendable {
        case aesGCM256 = "aes-gcm-256"
        case plaintext
    }

    public let url: URL
    public let exportedAt: Date
    public let byteCount: Int64?
    public let storageLocation: StorageLocation
    public let protection: Protection

    public var id: URL {
        url
    }

    public init(
        url: URL,
        exportedAt: Date,
        byteCount: Int64?,
        storageLocation: StorageLocation,
        protection: Protection,
    ) {
        self.url = url
        self.exportedAt = exportedAt
        self.byteCount = byteCount
        self.storageLocation = storageLocation
        self.protection = protection
    }
}

public struct AutomaticBackupCatalog: Hashable, Sendable {
    public let files: [AutomaticBackupFile]
    public let isICloudUnavailable: Bool

    public init(files: [AutomaticBackupFile], isICloudUnavailable: Bool) {
        self.files = files
        self.isICloudUnavailable = isICloudUnavailable
    }
}
