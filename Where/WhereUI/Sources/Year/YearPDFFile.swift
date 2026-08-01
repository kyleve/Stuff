import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A completed PDF on disk, exported with its exact content type so every
/// standard share destination receives a real PDF file and suggested name.
struct YearPDFFile: Hashable, Transferable {
    let url: URL
    let storageDirectory: URL
    let suggestedFilename: String
    let pageCount: Int

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(file.url)
        }
        .suggestedFileName { $0.suggestedFilename }
    }
}
