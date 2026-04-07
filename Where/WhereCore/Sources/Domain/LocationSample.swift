import Foundation

public struct LocationSample: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let jurisdiction: TaxJurisdiction

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        jurisdiction: TaxJurisdiction,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.jurisdiction = jurisdiction
    }
}
