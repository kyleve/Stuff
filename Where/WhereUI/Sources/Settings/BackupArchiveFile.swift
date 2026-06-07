import CoreTransferable
import UniformTypeIdentifiers

/// A whole-database backup that builds its `.zip` lazily, so `ShareLink(item:)`
/// can drive the export — and show the system's own "preparing…" progress —
/// instead of a custom `UIActivityViewController` bridge.
///
/// The archive bytes are only written when the share sheet resolves the item,
/// via the `build` closure (which wraps `WhereModel.exportBackup()`). Throwing
/// from `build` aborts the share.
struct BackupArchiveFile: Transferable {
    let build: @Sendable () async throws -> URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            try await SentTransferredFile(archive.build())
        }
    }
}
