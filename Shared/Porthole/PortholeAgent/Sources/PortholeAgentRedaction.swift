import Foundation
import PortholeCore

/// Removes known secrets from text and sensitive fields from structured tool output.
public struct PortholeAgentRedaction: Sendable {
    private let secrets: [String]

    public init(secrets: [String]) {
        self.secrets = secrets.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    func including(secret: String) -> Self {
        Self(secrets: secrets + [secret])
    }

    public func text(_ text: String) -> String {
        let known = secrets.reduce(text) { value, secret in value.replacingOccurrences(
            of: secret,
            with: "[REDACTED]",
        ) }
        return Self.tokenPattern.stringByReplacingMatches(
            in: known,
            range: NSRange(known.startIndex..., in: known),
            withTemplate: "[REDACTED]",
        )
    }

    public func value(_ value: PortholeValue) -> PortholeValue {
        switch value {
            case .null, .bool, .integer, .unsignedInteger, .number: value
            case let .string(value): .string(text(value))
            case let .array(values): .array(values.map(self.value))
            case let .object(values):
                .object(values.mapValues(self.value).merging(
                    values
                        .filter {
                            Self.sensitiveFields.contains($0.key.lowercased().filter(\.isLetter))
                        }
                        .mapValues { _ in .string("[REDACTED]") },
                    uniquingKeysWith: { _, redacted in redacted },
                ))
        }
    }

    func consume(_ buffer: inout String, flush: Bool) -> String {
        let retained = flush ? 0 : max(
            Self.tokenPrefixes.map(\.count).max() ?? 1,
            secrets.first?.count ?? 1,
        ) - 1
        var boundary = buffer.index(buffer.startIndex, offsetBy: max(0, buffer.count - retained))
        for secret in secrets {
            var search = buffer.startIndex ..< buffer.endIndex
            while let range = buffer.range(of: secret, range: search) {
                if range.lowerBound < boundary,
                   range.upperBound > boundary { boundary = range.lowerBound }
                search = range.upperBound ..< buffer.endIndex
            }
        }
        for match in Self.tokenPattern.matches(
            in: buffer,
            range: NSRange(buffer.startIndex..., in: buffer),
        ) {
            if let range = Range(match.range, in: buffer), range.lowerBound < boundary,
               range.upperBound > boundary { boundary = range.lowerBound }
        }
        if !flush {
            for prefix in Self.tokenPrefixes {
                var search = buffer.startIndex ..< buffer.endIndex
                while let range = buffer.range(of: prefix, range: search) {
                    let startsToken = range.lowerBound == buffer.startIndex || !Self
                        .tokenCharacter(buffer[buffer.index(before: range.lowerBound)])
                    if startsToken, buffer[range.upperBound...].allSatisfy(Self.tokenCharacter),
                       range.lowerBound < boundary { boundary = range.lowerBound }
                    search = range.upperBound ..< buffer.endIndex
                }
            }
        }
        let output = text(String(buffer[..<boundary]))
        buffer = String(buffer[boundary...])
        return output
    }

    func message(_ message: PortholeAgentMessage) -> PortholeAgentMessage {
        switch message {
            case let .user(content): .user(text: text(content))
            case let .assistant(content, calls):
                .assistant(text: text(content), toolCalls: calls.map { call in
                    PortholeAgentInvocation(
                        operationID: call.operationID,
                        callID: call.callID,
                        toolID: call.toolID,
                        arguments: value(call.arguments),
                    )
                })
            case let .tool(results):
                .tool(results: results.map { result in
                    PortholeAgentToolResult(
                        callID: result.callID,
                        toolID: result.toolID,
                        output: value(result.output),
                        isError: result.isError,
                    )
                })
        }
    }

    private static let sensitiveFields: Set<String> = [
        "apikey",
        "authorization",
        "password",
        "secret",
        "accesstoken",
        "refreshtoken",
        "privatekey",
        "credential",
        "credentials",
    ]

    private static let tokenPrefixes = [
        "ghp_",
        "gho_",
        "ghu_",
        "ghs_",
        "ghr_",
        "github_pat_",
        "sk-",
    ]
    private static let tokenPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "\\b(?:gh[pousr]_|github_pat_|sk-)[A-Za-z0-9_-]{20,}\\b",
            )
        } catch { preconditionFailure("Invalid bundled credential filter: \(error)") }
    }()

    private static func tokenCharacter(_ character: Character) -> Bool {
        character
            .isASCII &&
            (character.isLetter || character.isNumber || character == "_" || character == "-")
    }
}
