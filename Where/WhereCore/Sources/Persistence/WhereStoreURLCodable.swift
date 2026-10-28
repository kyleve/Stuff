import Foundation

/// A value whose stable identity is a single `store://` URL, so it persists and
/// round-trips as one compact, human-readable, searchable string instead of an
/// ad-hoc joined key (`type:value`) or a hand-written keyed `Codable`.
///
/// A conformer implements only the URL bridge (`storeURL` + `init?(storeURL:)`)
/// and gets `Codable` — a single-value URL string — for free from the extension
/// below. The same string doubles as a stable SwiftData column key (store the
/// `absoluteString`), which keeps `#Predicate` lookups a real query.
///
/// Build and parse the URL with ``StoreURL`` so every conformer shares one
/// `store://<collection>/<type>?<params>` shape. `DataIssueID` is the first
/// conformer; the pattern generalizes to any future store-object identity.
///
/// Lives in `WhereCore` because it is the Where store's identity convention;
/// it depends only on Foundation, so it can move to a shared module if another
/// feature needs the same `store://` scheme.
public protocol WhereStoreURLCodable: Codable {
    /// The `store://` URL that uniquely identifies this value.
    var storeURL: URL { get }
    /// Reconstruct from a `store://` URL, or `nil` if it doesn't name a valid
    /// value of this type.
    init?(storeURL: URL)
}

extension WhereStoreURLCodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let url = try container.decode(URL.self)
        guard let value = Self(storeURL: url) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a valid \(Self.self) store URL: \(url)",
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storeURL)
    }
}

/// Builder and parser for the `store://<collection>/<type>?<params>` identity
/// URLs used by ``WhereStoreURLCodable`` conformers.
///
/// `collection` is the object family (e.g. `issues`), `type` the specific kind
/// within it (e.g. `borderDrift`), and named query items carry the identifying
/// values — so a multi-value key (an issue spanning two days) is expressed as
/// distinct named params rather than positional, order-fragile substrings.
public enum StoreURL {
    public static let scheme = "store"

    /// The parsed components of a `store://` URL. A named struct (not a tuple)
    /// so it can carry across call boundaries per the repo's tuple rule.
    public struct Parts: Sendable, Hashable {
        public let collection: String
        public let type: String
        public let items: [String: String]

        public init(collection: String, type: String, items: [String: String]) {
            self.collection = collection
            self.type = type
            self.items = items
        }

        /// The value for a query item, or `nil` when the key is absent.
        public func value(_ key: String) -> String? {
            items[key]
        }
    }

    /// Build a `store://<collection>/<type>?<params>` URL. Query items are
    /// sorted by key so the same identity always produces the same string —
    /// required for stable SwiftData keys and byte-stable backup manifests.
    public static func url(collection: String, type: String, items: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = collection
        components.path = "/" + type
        components.queryItems = items.isEmpty
            ? nil
            : items
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        // The inputs are controlled identifiers and date strings, so a `nil`
        // here would be a programmer error (an illegal collection/type), not a
        // user-recoverable failure.
        guard let url = components.url else {
            preconditionFailure("Could not build store URL for \(collection)/\(type)")
        }
        return url
    }

    /// Parse a `store://` URL into its components, or `nil` if it isn't a
    /// well-formed `store://<collection>/<type>` URL.
    public static func parts(of url: URL) -> Parts? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let collection = components.host, !collection.isEmpty
        else { return nil }
        let path = components.path
        let type = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !type.isEmpty else { return nil }
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { items[item.name] = value }
        }
        return Parts(collection: collection, type: type, items: items)
    }
}
