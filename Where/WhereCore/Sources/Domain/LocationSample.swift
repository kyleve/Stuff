import Foundation

public struct LocationSample: Equatable, Sendable {
    public let timestamp: Date
    public let jurisdiction: TaxJurisdiction

    public init(timestamp: Date, jurisdiction: TaxJurisdiction) {
        self.timestamp = timestamp
        self.jurisdiction = jurisdiction
    }
}
