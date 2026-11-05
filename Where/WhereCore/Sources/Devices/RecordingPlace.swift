import Foundation
import RegionKit

/// A precise user-specified place with bounded historical validity. It supplies corroboration,
/// never observations or a source choice. Forecast homes and planned stays are separate values.
public struct RecordingPlace: Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, Comparable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        /// Persist the domain identity as a bare UUID.
        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(UUID.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var value = encoder.singleValueContainer()
            try value.encode(rawValue)
        }

        public static func < (
            lhs: Self,
            rhs: Self
        ) -> Bool {
            lhs.rawValue.uuidString < rhs.rawValue.uuidString
        }
    }

    public enum Kind: Hashable, Codable, Sendable {
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
        self.id = id
        self.kind = kind
        self.coordinate = coordinate
        self.validity = validity
        try validate()
    }

    public func validate() throws {
        try validity.validate()
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90 ... 90).contains(coordinate.latitude),
              (-180 ... 180).contains(coordinate.longitude)
        else { throw ValidationError.invalidCoordinate }
    }
}
