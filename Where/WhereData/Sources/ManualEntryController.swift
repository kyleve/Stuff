import Foundation
import UniformTypeIdentifiers
import WhereCore

public actor ManualEntryController: ManualEntryManaging {
    private let repository: any ManualLogEntryRepository
    private let evidenceController: EvidenceController

    public init(
        repository: any ManualLogEntryRepository,
        evidenceController: EvidenceController,
    ) {
        self.repository = repository
        self.evidenceController = evidenceController
    }

    public func records(in year: Int) async -> [ManualEntryRecord] {
        let entries = await repository.entries(in: year)
        var records: [ManualEntryRecord] = []
        records.reserveCapacity(entries.count)

        for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) {
            let attachments = await evidenceController.attachments(for: entry.id)
            records.append(
                ManualEntryRecord(
                    entry: entry,
                    attachments: attachments,
                ),
            )
        }

        return records
    }

    public func save(_ draft: ManualEntryDraft) async -> ManualEntryRecord {
        let entry = ManualLogEntry(
            id: draft.id ?? UUID(),
            timestamp: draft.timestamp,
            jurisdiction: draft.jurisdiction,
            note: draft.trimmedNote,
            kind: draft.kind,
        )

        await repository.save(entry)
        let attachments = await evidenceController.attachments(for: entry.id)
        return ManualEntryRecord(entry: entry, attachments: attachments)
    }

    public func deleteEntry(id: UUID) async {
        let attachments = await evidenceController.attachments(for: id)
        for attachment in attachments {
            await evidenceController.delete(attachment)
        }

        await repository.delete(id: id)
    }

    public func importEvidence(manualEntryID: UUID, fileURL: URL) async -> EvidenceAttachment? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey, .nameKey])
        let contentType = resourceValues?.contentType?.preferredMIMEType
            ?? UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let originalFilename = resourceValues?.name ?? fileURL.lastPathComponent

        return await evidenceController.importEvidence(
            manualEntryID: manualEntryID,
            originalFilename: originalFilename,
            contentType: contentType,
            data: data,
        )
    }

    public func evidenceFileURL(for attachment: EvidenceAttachment) async -> URL? {
        guard let data = await evidenceController.loadData(for: attachment) else {
            return nil
        }

        let sanitizedFilename = attachment.originalFilename.isEmpty ? attachment.id.uuidString : attachment.originalFilename
        let previewDirectory = FileManager.default.temporaryDirectory.appending(path: "WherePreview")

        do {
            try FileManager.default.createDirectory(
                at: previewDirectory,
                withIntermediateDirectories: true,
                attributes: nil,
            )
            let fileURL = previewDirectory.appending(path: "\(attachment.id.uuidString)-\(sanitizedFilename)")
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    public func deleteEvidence(_ attachment: EvidenceAttachment) async {
        await evidenceController.delete(attachment)
    }
}
