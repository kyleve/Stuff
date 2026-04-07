import Foundation

public struct ManualEntryDraft: Equatable, Sendable {
    public let id: UUID?
    public let timestamp: Date
    public let jurisdiction: TaxJurisdiction
    public let note: String
    public let kind: ManualLogEntry.Kind

    public init(
        id: UUID? = nil,
        timestamp: Date,
        jurisdiction: TaxJurisdiction,
        note: String = "",
        kind: ManualLogEntry.Kind,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.jurisdiction = jurisdiction
        self.note = note
        self.kind = kind
    }

    public init(entry: ManualLogEntry) {
        self.init(
            id: entry.id,
            timestamp: entry.timestamp,
            jurisdiction: entry.jurisdiction,
            note: entry.note ?? "",
            kind: entry.kind,
        )
    }

    public var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
