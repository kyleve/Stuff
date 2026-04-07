import Foundation

public struct ManualImportPackageManifest: Codable, Equatable, Sendable {
    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let timestamp: Date
        public let jurisdiction: Jurisdiction
        public let note: String?
        public let kind: ManualLogEntry.Kind
        public let evidenceFilenames: [String]

        public init(
            timestamp: Date,
            jurisdiction: Jurisdiction,
            note: String? = nil,
            kind: ManualLogEntry.Kind,
            evidenceFilenames: [String] = [],
        ) {
            self.timestamp = timestamp
            self.jurisdiction = jurisdiction
            self.note = note
            self.kind = kind
            self.evidenceFilenames = evidenceFilenames
        }
    }

    public enum Jurisdiction: Codable, Equatable, Sendable {
        case state(String)
        case unknown

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if value.caseInsensitiveCompare("unknown") == .orderedSame {
                self = .unknown
            } else {
                self = .state(value.uppercased())
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case let .state(rawValue):
                    try container.encode(rawValue)
                case .unknown:
                    try container.encode("UNKNOWN")
            }
        }

        public var displayValue: String {
            switch self {
                case let .state(rawValue):
                    rawValue
                case .unknown:
                    "UNKNOWN"
            }
        }

        public func resolve() -> TaxJurisdiction? {
            switch self {
                case let .state(rawValue):
                    guard let state = USState(rawValue: rawValue.uppercased()) else {
                        return nil
                    }
                    return .state(state)
                case .unknown:
                    return .unknown
            }
        }
    }
}
