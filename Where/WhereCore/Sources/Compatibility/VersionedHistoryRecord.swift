import Foundation

/// A stable outer envelope for future shared history contracts. Persistence stores the complete
/// envelope in one field, admitting its major before interpreting the kind or payload.
public struct VersionedHistoryRecord: Hashable, Codable, Sendable {
    struct Header: Decodable {
        let semantics: DataSemanticsVersion
    }

    struct GenerationHeader: Decodable {
        let dataGenerationID: WhereDataGenerationID
    }

    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let dataGenerationID: WhereDataGenerationID
    public let semantics: DataSemanticsVersion
    /// Stable review scope remains readable when an older payload has no safe interpretation.
    public enum Scope: Hashable, Codable, Sendable {
        case entireHistory
        case periods([RecordingPeriod])

        public func validate() throws {
            switch self {
                case .entireHistory: break
                case let .periods(periods):
                    guard !periods.isEmpty else { throw DataCompatibilityError.incompleteRecord }
                    for period in periods {
                        try period.validate()
                    }
            }
        }
    }

    public let scope: Scope
    /// Wire discriminator: unknown values remain opaque until their major is admitted.
    public let kind: String
    public let payload: Data

    public init(
        id: ID,
        dataGenerationID: WhereDataGenerationID,
        semantics: DataSemanticsVersion,
        scope: Scope,
        kind: String,
        payload: Data,
    ) {
        self.id = id
        self.dataGenerationID = dataGenerationID
        self.semantics = semantics
        self.scope = scope
        self.kind = kind
        self.payload = payload
    }

    public func decode<T: Decodable>(_ type: T.Type, policy: DataCompatibilityPolicy) throws -> T {
        try policy.decode(authoredWith: semantics) {
            try JSONDecoder().decode(type, from: payload)
        }
    }

    static func admit(_ data: Data, policy: DataCompatibilityPolicy) throws -> Self {
        let header = try JSONDecoder().decode(Header.self, from: data)
        try policy.validate(requiredMajor: header.semantics.major)
        let record = try JSONDecoder().decode(Self.self, from: data)
        try record.scope.validate()
        return record
    }

    /// Rebind an archive record to the importing generation without changing its operation.
    public func inGeneration(_ generationID: WhereDataGenerationID) -> Self {
        Self(
            id: id,
            dataGenerationID: generationID,
            semantics: semantics,
            scope: scope,
            kind: kind,
            payload: payload,
        )
    }
}
