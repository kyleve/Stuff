import Foundation

/// Positive observation-time calendar context, or its explicit withdrawal, for one device.
/// Context changes use the same causal interval semantics as user source choices.
public struct RecordingCalendarDecision: Hashable, Codable, Sendable {
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
        case establish(RecordingCalendarContext)
        case withdraw
    }

    public enum ValidationError: Error { case emptyScope }
    public let id: ID
    public let author: RecordingDeviceID
    public let deviceID: RecordingDeviceID
    public let periods: [RecordingPeriod]
    public let action: Action
    public let predecessors: Set<ID>
    public let version: DataSemanticsVersion

    public init(
        id: ID,
        author: RecordingDeviceID,
        deviceID: RecordingDeviceID,
        periods: [RecordingPeriod],
        action: Action,
        predecessors: Set<ID>,
        version: DataSemanticsVersion,
    ) throws {
        for period in periods {
            try period.validate()
        }
        self.id = id
        self.author = author
        self.deviceID = deviceID
        self.periods = RecordingPeriod.union(periods)
        self.action = action
        self.predecessors = predecessors
        self.version = version
        try validate()
    }

    public func validate() throws {
        guard !periods.isEmpty else { throw ValidationError.emptyScope }
        for period in periods {
            try period.validate()
        }
        if case let .establish(context) = action { try context.validate() }
    }
}

extension RecordingCalendarDecision: CausalPeriodOperation {}
