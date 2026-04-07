import Foundation

public struct ManualLogEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case supplemental
        case correction
    }

    public let id: UUID
    public let timestamp: Date
    public let jurisdiction: TaxJurisdiction
    public let note: String?
    public let kind: Kind

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        jurisdiction: TaxJurisdiction,
        note: String? = nil,
        kind: Kind,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.jurisdiction = jurisdiction
        self.note = note
        self.kind = kind
    }
}
