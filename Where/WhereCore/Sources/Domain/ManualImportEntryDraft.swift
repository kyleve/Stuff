import Foundation

public struct ManualImportEntryDraft: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let jurisdiction: TaxJurisdiction
    public let note: String
    public let kind: ManualLogEntry.Kind
    public let evidenceFiles: [URL]

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        jurisdiction: TaxJurisdiction,
        note: String = "",
        kind: ManualLogEntry.Kind,
        evidenceFiles: [URL] = [],
    ) {
        self.id = id
        self.timestamp = timestamp
        self.jurisdiction = jurisdiction
        self.note = note
        self.kind = kind
        self.evidenceFiles = evidenceFiles
    }

    public var manualEntryDraft: ManualEntryDraft {
        ManualEntryDraft(
            id: id,
            timestamp: timestamp,
            jurisdiction: jurisdiction,
            note: note,
            kind: kind,
        )
    }

    public var manualLogEntry: ManualLogEntry {
        ManualLogEntry(
            id: id,
            timestamp: timestamp,
            jurisdiction: jurisdiction,
            note: manualEntryDraft.trimmedNote,
            kind: kind,
        )
    }
}
