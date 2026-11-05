import Foundation

/// One immutable source-choice operation and its explicitly observed causal predecessors.
/// UUID operation identities avoid restoring a per-device counter. They are created only when
/// authoring a new operation; retries and imports must retain the original identity and payload.
public struct HistoryDecision: Hashable, Codable, Sendable {
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

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue.uuidString < rhs.rawValue.uuidString
        }
    }

    public enum Action: Hashable, Codable, Sendable {
        case select(RecordingDeviceID)
        case automatic
    }

    public enum Scope: Hashable, Codable, Sendable {
        case fixedPeriods
        /// The periods retain the complete calendar coverage approved at save time.
        case recordingDay(deviceID: RecordingDeviceID, day: CalendarDay)
    }

    public let id: ID
    public let author: RecordingDeviceID
    public let periods: [RecordingPeriod]
    public let scope: Scope
    public let action: Action
    // Canonical wire order keeps retries byte-identical across process hash seeds.
    let predecessorIDs: [ID]
    public var predecessors: Set<ID> {
        Set(predecessorIDs)
    }

    public let version: DataSemanticsVersion

    public init(
        id: ID,
        author: RecordingDeviceID,
        periods: [RecordingPeriod],
        scope: Scope,
        action: Action,
        predecessors: Set<ID>,
        version: DataSemanticsVersion,
    ) throws {
        for period in periods {
            try period.validate()
        }
        self.id = id
        self.author = author
        self.periods = RecordingPeriod.union(periods)
        self.scope = scope
        self.action = action
        predecessorIDs = predecessors.sorted()
        self.version = version
    }
}

extension HistoryDecision: CausalPeriodOperation {
    func action(at _: Date) -> Action {
        action
    }
}
