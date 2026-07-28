import Foundation

/// A key in ``LogSession/attributes`` — typed so a key can't silently typo
/// into a new, untracked one. Apps add their own:
///
/// ```swift
/// extension LogSessionAttributeKey {
///     static let deviceTier = LogSessionAttributeKey("device-tier")
/// }
/// ```
public struct LogSessionAttributeKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

extension LogSessionAttributeKey {
    /// The commit the app was built from.
    public static let commit = LogSessionAttributeKey("commit")
    /// Whether that commit's working tree was clean or dirty at build time —
    /// two sessions from one SHA aren't the same code if it was dirty. Values
    /// are ``CommitStatus`` raw values.
    public static let commitStatus = LogSessionAttributeKey("commit-status")
    /// The build configuration (`Debug` / `Release`).
    public static let configuration = LogSessionAttributeKey("configuration")
    /// `SWIFT_OPTIMIZATION_LEVEL` (`-Onone`, `-O`, `-Osize`) — the one thing
    /// that decides whether a span's duration says anything about
    /// production. A `Debug` configuration can still be compiled with `-O`,
    /// so the configuration alone can't answer it.
    public static let optimizationLevel = LogSessionAttributeKey("optimization-level")
    /// `SWIFT_COMPILATION_MODE` — `wholemodule`, or one of the per-file modes
    /// (`singlefile` is what a stock Debug build reports). Left untyped: the
    /// value is whatever the toolchain named, and a new mode should land in the
    /// log rather than be dropped for not matching a known case.
    public static let compilationMode = LogSessionAttributeKey("compilation-mode")

    /// The values ``LogSessionAttributeKey/commitStatus`` takes.
    ///
    /// A well-known key is only well-known if its values are too: the app that
    /// writes the attribute and the tooling that reads it sit in different
    /// modules, so leaving the vocabulary as bare strings makes them two
    /// independent literals that can drift without a compile error.
    public enum CommitStatus: String, Hashable, Sendable, CaseIterable {
        case clean
        case dirty
    }
}

/// Lets a session's attributes encode as a plain JSON object keyed by the
/// attribute name — see ``StringCodingKey``.
extension LogSessionAttributeKey: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(codingKey.stringValue)
    }
}
