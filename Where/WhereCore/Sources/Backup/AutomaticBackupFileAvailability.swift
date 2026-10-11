import Foundation

/// Metadata-only preflight. Catalog reads must not download evicted iCloud files.
public protocol AutomaticBackupFileAvailabilityChecking: Sendable {
    func isDownloaded(at url: URL) throws -> Bool
}

public struct SystemAutomaticBackupFileAvailability: AutomaticBackupFileAvailabilityChecking {
    public init() {}

    public func isDownloaded(at url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus != .notDownloaded
    }
}
