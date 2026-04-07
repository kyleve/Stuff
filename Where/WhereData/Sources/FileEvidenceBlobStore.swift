import Foundation
import WhereCore

public actor FileEvidenceBlobStore: EvidenceFileStore {
    private let baseDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        baseDirectoryURL: URL,
        fileManager: FileManager = .default,
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
    }

    public func save(_ data: Data, for attachment: EvidenceAttachment) async {
        let destination = fileURL(for: attachment)

        do {
            try fileManager.createDirectory(
                at: baseDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil,
            )
            try data.write(to: destination, options: .atomic)
        } catch {
            assertionFailure("Failed to save evidence blob at \(destination.path): \(error)")
        }
    }

    public func load(for attachment: EvidenceAttachment) async -> Data? {
        try? Data(contentsOf: fileURL(for: attachment))
    }

    public func delete(for attachment: EvidenceAttachment) async {
        try? fileManager.removeItem(at: fileURL(for: attachment))
    }

    private func fileURL(for attachment: EvidenceAttachment) -> URL {
        baseDirectoryURL.appending(path: attachment.storageKey)
    }
}
