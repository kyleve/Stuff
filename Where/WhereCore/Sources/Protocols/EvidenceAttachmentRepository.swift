import Foundation

public protocol EvidenceAttachmentRepository: Sendable {
    func attachments(for manualEntryID: UUID) async -> [EvidenceAttachment]
    func attachments(for manualEntryIDs: [UUID]) async -> [EvidenceAttachment]
    func save(_ attachment: EvidenceAttachment) async
    func delete(id: UUID) async
}
