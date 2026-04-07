import Foundation

public struct ManualEntryRecord: Equatable, Sendable, Identifiable {
    public let entry: ManualLogEntry
    public let attachments: [EvidenceAttachment]

    public init(
        entry: ManualLogEntry,
        attachments: [EvidenceAttachment],
    ) {
        self.entry = entry
        self.attachments = attachments
    }

    public var id: UUID {
        entry.id
    }
}
