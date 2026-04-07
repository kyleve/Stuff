import Foundation
import WhereCore

public actor EvidenceController {
    private let attachmentRepository: any EvidenceAttachmentRepository
    private let fileStore: any EvidenceFileStore

    public init(
        attachmentRepository: any EvidenceAttachmentRepository,
        fileStore: any EvidenceFileStore,
    ) {
        self.attachmentRepository = attachmentRepository
        self.fileStore = fileStore
    }

    public func attachments(for manualEntryID: UUID) async -> [EvidenceAttachment] {
        await attachmentRepository.attachments(for: manualEntryID)
    }

    public func importEvidence(
        manualEntryID: UUID,
        originalFilename: String,
        contentType: String,
        data: Data,
        createdAt: Date = Date(),
    ) async -> EvidenceAttachment {
        let attachment = EvidenceAttachment(
            manualEntryID: manualEntryID,
            originalFilename: originalFilename,
            contentType: contentType,
            byteCount: data.count,
            createdAt: createdAt,
        )

        await attachmentRepository.save(attachment)
        await fileStore.save(data, for: attachment)
        return attachment
    }

    public enum BatchImportError: Error, Sendable {
        case couldNotPersistEvidence
    }

    public func importEvidence(
        _ requests: [(manualEntryID: UUID, originalFilename: String, contentType: String, data: Data, createdAt: Date)],
    ) async throws -> [EvidenceAttachment] {
        let attachments = requests.map { request in
            EvidenceAttachment(
                manualEntryID: request.manualEntryID,
                originalFilename: request.originalFilename,
                contentType: request.contentType,
                byteCount: request.data.count,
                createdAt: request.createdAt,
            )
        }

        guard !attachments.isEmpty else {
            return []
        }

        await attachmentRepository.save(attachments)

        for (attachment, request) in zip(attachments, requests) {
            await fileStore.save(request.data, for: attachment)
            guard await fileStore.load(for: attachment) != nil else {
                for persistedAttachment in attachments {
                    await attachmentRepository.delete(id: persistedAttachment.id)
                    await fileStore.delete(for: persistedAttachment)
                }
                throw BatchImportError.couldNotPersistEvidence
            }
        }

        return attachments
    }

    public func loadData(for attachment: EvidenceAttachment) async -> Data? {
        await fileStore.load(for: attachment)
    }

    public func delete(_ attachment: EvidenceAttachment) async {
        await attachmentRepository.delete(id: attachment.id)
        await fileStore.delete(for: attachment)
    }
}
