import CoreTransferable
import UniformTypeIdentifiers

/// A ready-on-disk backup archive shared through `ShareLink`. The export is
/// built up-front (see `BackupModel.exportBackup`), so this just wraps the
/// finished file — but wrapping it in an explicit `.zip` `FileRepresentation`,
/// rather than sharing a bare `URL`, keeps the exported content type declared
/// instead of inferred from the filename extension.
///
/// `suggestedFileName` is load-bearing: sharing a custom `Transferable` (rather
/// than a bare `URL`) means many share targets ignore the file's on-disk name
/// and synthesize one from the `SharePreview` title. Forwarding the archive's
/// real name (`Where Backup <date> <time>.zip`, see `BackupService`) keeps the
/// date/time stamp instead of a generic "Where Backup".
struct BackupArchiveFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            SentTransferredFile(archive.url)
        }
        .suggestedFileName { $0.url.lastPathComponent }
    }
}
