import Foundation

public struct DailyJurisdictionRecord: Equatable, Sendable {
    public let date: Date
    public let jurisdictions: [TaxJurisdiction]

    public init(date: Date, jurisdictions: [TaxJurisdiction]) {
        self.date = date
        self.jurisdictions = jurisdictions
    }
}
