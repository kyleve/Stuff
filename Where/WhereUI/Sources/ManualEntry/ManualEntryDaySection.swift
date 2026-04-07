import Foundation
import WhereCore

public struct ManualEntryDaySection: Equatable, Sendable, Identifiable {
    public let date: Date
    public let trackedJurisdictions: [TaxJurisdiction]
    public let finalJurisdictions: [TaxJurisdiction]
    public let note: String?
    public let changesTrackedOutcome: Bool
    public let entries: [ManualEntryDayRecord]

    public init(
        date: Date,
        trackedJurisdictions: [TaxJurisdiction],
        finalJurisdictions: [TaxJurisdiction],
        note: String?,
        changesTrackedOutcome: Bool,
        entries: [ManualEntryDayRecord],
    ) {
        self.date = date
        self.trackedJurisdictions = trackedJurisdictions
        self.finalJurisdictions = finalJurisdictions
        self.note = note
        self.changesTrackedOutcome = changesTrackedOutcome
        self.entries = entries
    }

    public var id: Date {
        date
    }
}
