import Foundation

/// Where each `LocationSample` came from. Recorded so reports can distinguish
/// passive GPS data from user-asserted history.
public enum SampleSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// A `CLVisit` arrival callback.
    case gpsVisit
    /// A `CLLocationManager` significant-change callback.
    case gpsSignificantChange
    /// User typed in a coordinate or picked a place after the fact.
    case manual
    /// Derived from an attached piece of evidence (e.g. a boarding pass).
    case evidenceImplied
}

/// A single point-in-time observation of where the user was. The smallest
/// unit of data that flows through `WhereCore` and `WhereData`.
public struct LocationSample: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let coordinate: Coordinate
    public let horizontalAccuracy: Double
    public let source: SampleSource

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        coordinate: Coordinate,
        horizontalAccuracy: Double = 0,
        source: SampleSource,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
    }
}
