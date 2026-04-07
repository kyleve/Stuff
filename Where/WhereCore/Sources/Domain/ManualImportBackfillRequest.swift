import Foundation

public struct ManualImportBackfillRequest: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let jurisdiction: TaxJurisdiction
    public let note: String
    public let kind: ManualLogEntry.Kind
    public let evidenceFiles: [URL]

    public init(
        startDate: Date,
        endDate: Date,
        jurisdiction: TaxJurisdiction,
        note: String = "",
        kind: ManualLogEntry.Kind,
        evidenceFiles: [URL] = [],
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.jurisdiction = jurisdiction
        self.note = note
        self.kind = kind
        self.evidenceFiles = evidenceFiles
    }
}
