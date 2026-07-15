import CoreTransferable
import UniformTypeIdentifiers

/// A ready-on-disk backup archive shared through `ShareLink`. The export is
/// built up-front (see `BackupModel.exportBackup`), so this just wraps the
/// finished file — but wrapping it in an explicit `.zip` `FileRepresentation`,
/// rather than sharing a bare `URL`, keeps the exported content type declared
/// instead of inferred from the filename extension.
struct BackupArchiveFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            SentTransferredFile(archive.url)
        }
    }
}
