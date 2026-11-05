import Foundation
import RegionKit

/// A causal edit to one precise place. A deletion restores no place evidence only within its
/// reviewed periods. Concurrent different definitions remain unresolved, never timestamp winners.
public struct RecordingPlaceDecision: Hashable, Codable, Sendable {
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

    public enum Action: Hashable, Codable, Sendable {
        case set(kind: RecordingPlace.Kind, coordinate: Coordinate)
        case remove
    }

    public enum ValidationError: Error { case emptyScope }
    public let id: ID
    public let author: RecordingDeviceID
    public let placeID: RecordingPlace.ID
    public let periods: [RecordingInterval]
    public let action: Action
    let predecessorIDs: [ID]
    public var predecessors: Set<ID> {
        Set(predecessorIDs)
    }

    public let version: DataSemanticsVersion

    public init(
        id: ID,
        author: RecordingDeviceID,
        placeID: RecordingPlace.ID,
        validity: [RecordingInterval],
        action: Action,
        predecessors: Set<ID>,
        version: DataSemanticsVersion,
    ) throws {
        for period in validity {
            try period.validate()
        }
        self.id = id
        self.author = author
        self.placeID = placeID
        periods = RecordingInterval.union(validity)
        self.action = action
        predecessorIDs = predecessors.sorted()
        self.version = version
        try validate()
    }

    public init(
        id: ID,
        author: RecordingDeviceID,
        placeID: RecordingPlace.ID,
        periods: [RecordingPeriod],
        action: Action,
        predecessors: Set<ID>,
        version: DataSemanticsVersion,
    ) throws {
        try self.init(
            id: id,
            author: author,
            placeID: placeID,
            validity: periods.map(RecordingInterval.init),
            action: action,
            predecessors: predecessors,
            version: version,
        )
    }

    public func validate() throws {
        guard !periods.isEmpty else { throw ValidationError.emptyScope }
        for period in periods {
            try period.validate()
            if case let .set(kind, coordinate) = action {
                _ = try RecordingPlace(
                    id: placeID,
                    kind: kind,
                    coordinate: coordinate,
                    validity: period,
                )
            }
        }
    }
}

extension RecordingPlaceDecision: CausalPeriodOperation {
    func action(at _: Date) -> Action {
        action
    }
}
