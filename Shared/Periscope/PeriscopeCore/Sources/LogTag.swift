import Foundation

/// A typed tag key — apps declare their keys once so a tag can't silently
/// typo into a new, untracked identifier:
///
/// ```swift
/// extension LogTagKey {
///     static let paymentID = LogTagKey("payment-id")
/// }
/// ```
public struct LogTagKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

/// One key/value tag pair, as stored and queried.
///
/// Tags are orthogonal to the scope hierarchy: a tagged context stamps every
/// event logged through it (e.g. the current payment's ID across a whole UI
/// flow), and any event can carry any tags regardless of where it sits in
/// the tree.
public struct LogTag: Hashable, Sendable, Codable {
    public let key: LogTagKey
    public let value: String

    public init(key: LogTagKey, value: String) {
        self.key = key
        self.value = value
    }
}
