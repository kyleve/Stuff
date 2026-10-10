/// Author-approved export eligibility and the controls that must all be enabled.
/// These requirements describe a schema, not an inspection of the field's contents.
public enum LogExportRequirements: Equatable, Sendable {
    case baseline(requiring: Set<LogExportControl>)
    case diagnostic(requiring: Set<LogExportControl>)
    case never

    /// Conservative defaults for the existing declaration and emission classifications.
    public static func classified(exposure: LogFieldExposure, kind: LogFieldKind) -> Self {
        if exposure == .shareable { return .baseline(requiring: []) }
        switch kind {
            case .identifier: return .diagnostic(requiring: [.identifiers])
            case .location: return .diagnostic(requiring: [.location])
            case .userContent: return .diagnostic(requiring: [.userContent])
            case .boolean, .count, .limit, .duration, .category:
                return .diagnostic(requiring: [])
            case .pii, .json, .errorDetails, .dateTime, .pathOrURL, .arbitraryText, .domainValue,
                 .technicalState:
                return .diagnostic(requiring: [.personalData])
        }
    }

    /// A child cannot weaken its parent's eligibility or remove a required control.
    public func constrained(by parent: Self) -> Self {
        switch (self, parent) {
            case (.never, _), (_, .never):
                .never
            case let (.baseline(child), .baseline(parent)):
                .baseline(requiring: child.union(parent))
            case let (.baseline(child), .diagnostic(parent)),
                 let (.diagnostic(child), .baseline(parent)),
                 let (.diagnostic(child), .diagnostic(parent)):
                .diagnostic(requiring: child.union(parent))
        }
    }
}

/// Stable requirement tags and sorted control identities, independent of associated-value coding.
extension LogExportRequirements: Codable {
    private enum CodingKeys: String, CodingKey { case mode, controls }
    private enum Mode: String, Codable { case baseline, diagnostic, never }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
            case .never: self = .never
            case .baseline:
                self = try .baseline(requiring: Set(container.decode(
                    [LogExportControl].self,
                    forKey: .controls,
                )))
            case .diagnostic:
                self = try .diagnostic(requiring: Set(container.decode(
                    [LogExportControl].self,
                    forKey: .controls,
                )))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .never: try container.encode(Mode.never, forKey: .mode)
            case let .baseline(controls):
                try container.encode(Mode.baseline, forKey: .mode)
                try container.encode(
                    controls.sorted { $0.rawValue < $1.rawValue },
                    forKey: .controls,
                )
            case let .diagnostic(controls):
                try container.encode(Mode.diagnostic, forKey: .mode)
                try container.encode(
                    controls.sorted { $0.rawValue < $1.rawValue },
                    forKey: .controls,
                )
        }
    }
}
