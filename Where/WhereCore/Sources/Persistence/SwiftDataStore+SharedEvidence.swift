import Foundation
import SwiftData

extension SwiftDataStore {
    public func sharedEvidenceImportReceipt(for draftID: SharedEvidenceDraft.ID) async throws
        -> SharedEvidenceDraft.Receipt?
    {
        let rawID = draftID.rawValue
        let rows = try readContext().fetch(FetchDescriptor<SDSharedEvidenceImportReceipt>(
            predicate: #Predicate { $0.draftID == rawID },
        ))
        var receipt: SharedEvidenceDraft.Receipt?
        for row in rows {
            guard let digest = row.digest else { throw DataCompatibilityError.incompleteRecord }
            let value = SharedEvidenceDraft.Receipt(draftID: draftID, digest: digest)
            if let receipt, receipt != value { throw DataCompatibilityError.conflictingRecord }
            receipt = value
        }
        return receipt
    }

    public func addSharedEvidenceImportReceipt(_ receipt: SharedEvidenceDraft
        .Receipt) async throws
    {
        let context = mutationContext()
        if let existing = try await sharedEvidenceImportReceipt(for: receipt.draftID) {
            guard existing == receipt else { throw DataCompatibilityError.conflictingRecord }
            return
        }
        let row = SDSharedEvidenceImportReceipt()
        row.draftID = receipt.draftID.rawValue
        row.digest = receipt.digest
        context.insert(row)
    }
}

/// Internal delivery receipts are not user history. Keep them across Reset/Replace and evidence
/// deletion, and omit them from lossless user backups (the pending inbox is backup-excluded too).
@Model
final class SDSharedEvidenceImportReceipt {
    var draftID: UUID?
    var digest: Data?
    init() {}
}
