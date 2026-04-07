import Foundation

public struct DailyStateLedger: Equatable, Sendable, Identifiable {
    public let date: Date
    public let trackedJurisdictions: [TaxJurisdiction]
    public let manualEntries: [ManualLogEntry]
    public let finalJurisdictions: [TaxJurisdiction]
    public let note: String?

    public init(
        date: Date,
        trackedJurisdictions: [TaxJurisdiction],
        manualEntries: [ManualLogEntry],
        finalJurisdictions: [TaxJurisdiction],
        note: String?,
    ) {
        self.date = date
        self.trackedJurisdictions = trackedJurisdictions
        self.manualEntries = manualEntries
        self.finalJurisdictions = finalJurisdictions
        self.note = note
    }

    public var id: Date {
        date
    }

    public var needsReview: Bool {
        finalJurisdictions.contains(.unknown)
    }
}
