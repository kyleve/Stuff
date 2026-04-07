import Foundation

public protocol ManualEntryManaging: Sendable {
    func records(in year: Int) async -> [ManualEntryRecord]
    func save(_ draft: ManualEntryDraft) async -> ManualEntryRecord
    func deleteEntry(id: UUID) async
    func importEvidence(manualEntryID: UUID, fileURL: URL) async -> EvidenceAttachment?
    func evidenceFileURL(for attachment: EvidenceAttachment) async -> URL?
    func deleteEvidence(_ attachment: EvidenceAttachment) async
}
