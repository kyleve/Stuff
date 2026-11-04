import Foundation
import RegionKit

/// A precise user-specified place with bounded historical validity. It supplies corroboration,
/// never observations or a source choice. Forecast homes and planned stays are separate values.
public struct RecordingPlace: Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public enum Kind: Hashable, Sendable {
        case regularHome
        case temporaryBase
    }

    public enum ValidationError: Error {
        case invalidCoordinate
    }

    public let id: ID
    public let kind: Kind
    public let coordinate: Coordinate
    public let validity: RecordingPeriod

    public init(id: ID, kind: Kind, coordinate: Coordinate, validity: RecordingPeriod) throws {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90 ... 90).contains(coordinate.latitude),
              (-180 ... 180).contains(coordinate.longitude)
        else { throw ValidationError.invalidCoordinate }
        self.id = id
        self.kind = kind
        self.coordinate = coordinate
        self.validity = validity
    }
}
