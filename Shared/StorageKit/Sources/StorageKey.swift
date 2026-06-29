import Foundation

/// A filesystem-safe, single path component used to name a `StorageSystem` and
/// every container in its tree.
///
/// Honors the repo's "typed keys, not raw `String`" rule: prefer building one
/// from a typed enum (`StorageKey(MyKeys.logs)`); the string-literal convenience
/// (`"logs"`) is for call-site brevity. The raw input is sanitized into a safe
/// single path component — path separators (`/`, `\`), `:`, and control
/// characters become `_`, and an empty / `.` / `..` input gets a leading `_` —
/// so a key can never traverse out of its parent directory.
///
/// Sanitization is normalization, not validation: two different raw inputs can
/// sanitize to the same `name` (e.g. `"a/b"` and `"a_b"`), so keep your keys
/// distinct.
public struct StorageKey: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The sanitized path component, used both on disk and as this node's
    /// key-value suite-name segment.
    public let name: String

    public init(_ raw: String) {
        name = Self.sanitized(raw)
    }

    public init(_ key: some RawRepresentable<String>) {
        self.init(key.rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        name
    }

    private static func sanitized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        result.unicodeScalars.reserveCapacity(trimmed.unicodeScalars.count)
        for scalar in trimmed.unicodeScalars {
            if scalar == "/" || scalar == "\\" || scalar == ":" || scalar.value < 0x20 {
                result.unicodeScalars.append("_")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        if result.isEmpty || result == "." || result == ".." {
            return "_" + result
        }
        return result
    }
}
