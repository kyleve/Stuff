import CryptoKit
import Foundation

/// Authentication results from one retention scan. A deletion is authorized
/// only while its candidate and all three retained archives still match.
struct AutomaticBackupRetention {
    struct VerifiedFile {
        let file: AutomaticBackupFile
        let digest: SHA256.Digest
        let exportedAt: Date
    }

    let verified: [VerifiedFile]
    let retainedFileCount: Int

    func prune() async throws {
        precondition(retainedFileCount > 0)
        let ordered = verified.sorted {
            if $0.exportedAt == $1.exportedAt { return $0.file.url.path < $1.file.url.path }
            return $0.exportedAt > $1.exportedAt
        }
        let keepers = Array(ordered.prefix(retainedFileCount))
        for candidate in ordered.dropFirst(retainedFileCount) {
            try Task.checkCancellation()
            try await CoordinatedBackupFileAccess.delete(
                at: candidate.file.url,
                keeping: keepers.map(\.file.url),
            ) { candidateURL, keeperURLs, progress in
                for (keeper, url) in zip(keepers, keeperURLs) {
                    if progress.isCancelled { throw CancellationError() }
                    guard try Self.digest(at: url) == keeper.digest else { return }
                }
                guard try Self.digest(at: candidateURL) == candidate.digest else { return }
                if progress.isCancelled { throw CancellationError() }
                try FileManager.default.removeItem(at: candidateURL)
            }
        }
    }

    private static func digest(at url: URL) throws -> SHA256.Digest {
        try SHA256.hash(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}
