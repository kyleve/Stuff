import Foundation

/// One immutable source-choice operation and its explicitly observed causal predecessors.
/// UUID operation identities avoid restoring a per-device counter. They are created only when
/// authoring a new operation; retries and imports must retain the original identity and payload.
public struct HistoryDecision: Hashable, Sendable {
    public struct ID: Hashable, Sendable, Comparable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue.uuidString < rhs.rawValue.uuidString
        }
    }

    public enum Action: Hashable, Sendable {
        case select(RecordingDeviceID)
        case automatic
    }

    public let id: ID
    public let author: RecordingDeviceID
    public let periods: [RecordingPeriod]
    public let action: Action
    public let predecessors: Set<ID>
    public let version: DataSemanticsVersion

    public init(
        id: ID,
        author: RecordingDeviceID,
        periods: [RecordingPeriod],
        action: Action,
        predecessors: Set<ID>,
        version: DataSemanticsVersion,
    ) {
        self.id = id
        self.author = author
        self.periods = RecordingPeriod.union(periods)
        self.action = action
        self.predecessors = predecessors
        self.version = version
    }
}
