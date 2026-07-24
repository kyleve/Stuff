import Foundation
import PortholeCore

/// A parsed `connector/member` reference from the command line.
public struct ParsedRef: Equatable {
    public var connector: String
    public var member: String

    public init(connector: String, member: String) {
        self.connector = connector
        self.member = member
    }

    public var actionRef: PortholeActionRef {
        PortholeActionRef(
            connector: PortholeConnectorID(connector),
            action: PortholeActionID(member),
        )
    }

    public var dataSourceRef: PortholeDataSourceRef {
        PortholeDataSourceRef(
            connector: PortholeConnectorID(connector),
            source: PortholeDataSourceID(member),
        )
    }
}

/// Errors from parsing command-line values.
public enum CLIParsingError: Error, Equatable, CustomStringConvertible {
    case malformedRef(String)
    case malformedParameter(String)
    case invalidJSON(String)

    public var description: String {
        switch self {
            case let .malformedRef(value):
                "Expected `connector/name`, got `\(value)`."
            case let .malformedParameter(value):
                "Expected `key=value`, got `\(value)`."
            case let .invalidJSON(value):
                "Not valid JSON: \(value)"
        }
    }
}

public enum CLIValueParsing {
    /// Parses `connector/member` (exactly one slash, both sides non-empty).
    public static func parseRef(_ string: String) throws -> ParsedRef {
        let parts = string.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw CLIParsingError.malformedRef(string)
        }
        return ParsedRef(connector: String(parts[0]), member: String(parts[1]))
    }

    /// Interprets a bare CLI token: `true`/`false` → bool, an integer → int, a
    /// decimal → double, otherwise a string.
    public static func parseScalar(_ string: String) -> PortholeValue {
        if string == "true" { return .bool(true) }
        if string == "false" { return .bool(false) }
        if let int = Int64(string) { return .int(int) }
        if let double = Double(string),
           string.contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
        {
            return .double(double)
        }
        return .string(string)
    }

    /// Parses one `key=value` pair; the value uses `parseScalar`.
    public static func parseParameter(_ string: String) throws
        -> (key: String, value: PortholeValue)
    {
        guard let separator = string.firstIndex(of: "=") else {
            throw CLIParsingError.malformedParameter(string)
        }
        let key = String(string[string.startIndex ..< separator])
        guard !key.isEmpty else { throw CLIParsingError.malformedParameter(string) }
        let rawValue = String(string[string.index(after: separator)...])
        return (key, parseScalar(rawValue))
    }

    /// Decodes a JSON string into a `PortholeValue`.
    public static func parseJSON(_ string: String) throws -> PortholeValue {
        guard let data = string.data(using: .utf8)
        else { throw CLIParsingError.invalidJSON(string) }
        do {
            return try JSONDecoder().decode(PortholeValue.self, from: data)
        } catch {
            throw CLIParsingError.invalidJSON(string)
        }
    }

    /// Builds a parameters object from an optional base `--json` object plus
    /// `--param key=value` overrides.
    public static func buildParameters(json: String?, params: [String]) throws -> PortholeValue {
        var object: [String: PortholeValue] = [:]
        if let json {
            guard case let .object(base) = try parseJSON(json) else {
                throw CLIParsingError.invalidJSON("expected a JSON object")
            }
            object = base
        }
        for pair in params {
            let (key, value) = try parseParameter(pair)
            object[key] = value
        }
        return .object(object)
    }
}
