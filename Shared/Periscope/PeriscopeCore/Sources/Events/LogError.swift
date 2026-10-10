import Foundation

/// A restricted, immutable error snapshot captured at the logging boundary.
/// This is diagnostic data, not a replacement for the original error in application state.
public struct LogError: Codable, Equatable, Sendable {
    public struct DecodingDetails: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case typeMismatch = "type_mismatch"
            case valueNotFound = "value_not_found"
            case keyNotFound = "key_not_found"
            case dataCorrupted = "data_corrupted"
            case unknown
        }

        /// Preserves both representations supplied by CodingKey, including array indices.
        public struct PathComponent: Codable, Equatable, Sendable {
            public let stringValue: String
            public let intValue: Int?

            private enum CodingKeys: String, CodingKey {
                case stringValue = "string_value"
                case intValue = "int_value"
            }

            fileprivate init(_ key: any CodingKey) {
                stringValue = key.stringValue
                intValue = key.intValue
            }
        }

        public let kind: Kind
        /// For a missing key, the path includes that key as its final component.
        public let codingPath: [PathComponent]
        public let description: String

        private enum CodingKeys: String, CodingKey {
            case kind, description
            case codingPath = "coding_path"
        }

        fileprivate init(_ error: DecodingError) {
            switch error {
                case let .typeMismatch(_, context):
                    kind = .typeMismatch
                    codingPath = context.codingPath.map(PathComponent.init)
                    description = context.debugDescription
                case let .valueNotFound(_, context):
                    kind = .valueNotFound
                    codingPath = context.codingPath.map(PathComponent.init)
                    description = context.debugDescription
                case let .keyNotFound(key, context):
                    kind = .keyNotFound
                    codingPath = (context.codingPath + [key]).map(PathComponent.init)
                    description = context.debugDescription
                case let .dataCorrupted(context):
                    kind = .dataCorrupted
                    codingPath = context.codingPath.map(PathComponent.init)
                    description = context.debugDescription
                @unknown default:
                    kind = .unknown
                    codingPath = []
                    description = "Unrecognized decoding error; see the enclosing error diagnostics"
            }
        }
    }

    public enum CauseOmission: String, Codable, Sendable {
        case cycle
        case depthLimit = "depth_limit"
        case nodeLimit = "node_limit"
    }

    public let domain: String
    public let code: Int
    public let description: String
    public let failureReason: String?
    public let recoverySuggestion: String?
    public let causes: [LogError]
    public let omittedCauses: [CauseOmission]
    public let details: JSONValue?
    public let decoding: DecodingDetails?

    private enum CodingKeys: String, CodingKey {
        case domain
        case code
        case description
        case causes
        case details
        case decoding
        case failureReason = "failure_reason"
        case recoverySuggestion = "recovery_suggestion"
        case omittedCauses = "omitted_causes"
    }

    public init(capturing error: any Error) {
        self.init(capturing: error, details: nil)
    }

    /// Details are explicitly supplied by the caller. Arbitrary `userInfo` is never copied.
    /// Prefer concrete event fields for domain-specific data with a known schema.
    public init(capturing error: any Error, details: JSONValue?) {
        var remainingNodes = Self.maximumNodeCount
        self.init(
            error: error,
            details: details,
            ancestors: [],
            remainingNodes: &remainingNodes,
        )
    }

    // Bound captured error trees, including the root, before they enter the logging buffer.
    private static let maximumNodeCount = 32
    private static let maximumDepth = 8

    private init(
        error original: any Error,
        details: JSONValue?,
        ancestors: [NSError],
        remainingNodes: inout Int,
    ) {
        remainingNodes -= 1
        let error = original as NSError
        domain = error.domain
        code = error.code
        description = error.localizedDescription
        failureReason = error.localizedFailureReason
        recoverySuggestion = error.localizedRecoverySuggestion
        self.details = details
        decoding = (original as? DecodingError).map(DecodingDetails.init)

        // Retain ancestors while comparing identity, including bridged Swift errors.
        let path = ancestors + [error]
        var captured: [LogError] = []
        var omissions: [CauseOmission] = []
        var underlying: [any Error] = []
        if let cause = error.userInfo[NSUnderlyingErrorKey] as? any Error {
            underlying.append(cause)
        }
        if let causes = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [any Error] {
            underlying.append(contentsOf: causes)
        }
        for cause in underlying {
            let bridged = cause as NSError
            if path.contains(where: { $0 === bridged }) {
                omissions.append(.cycle)
                break
            } else if path.count >= Self.maximumDepth {
                omissions.append(.depthLimit)
                break
            } else if remainingNodes == 0 {
                omissions.append(.nodeLimit)
                break
            } else {
                captured.append(LogError(
                    error: cause,
                    details: nil,
                    ancestors: path,
                    remainingNodes: &remainingNodes,
                ))
            }
        }
        causes = captured
        omittedCauses = omissions
    }
}
