import Foundation

/// Builder and parser for `region://<collection>/<type>?<params>` identity URLs
/// — RegionKit's local analog of WhereCore's `StoreURL`. It lets a RegionKit
/// value vend a stable, namespaced URL identity (e.g. a Periscope
/// `LogEvent.externalID`) without reaching up into app code for `StoreURL`.
///
/// `collection` is the object family (`regions`), `type` the specific instance
/// or kind within it, and named query items carry any additional identifying
/// values. RegionKit is a standalone lower module, so it owns its own
/// `region://` scheme rather than borrowing the app's `store://` one — the two
/// are intentionally separate namespaces (a region is a bundled-catalog entry,
/// not a store row).
public enum RegionURL {
    public static let scheme = "region"

    /// The parsed components of a `region://` URL. A named struct (not a tuple)
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

    /// Build a `region://<collection>/<type>?<params>` URL. Query items are
    /// sorted by key so the same identity always produces the same string.
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
        // The inputs are controlled identifiers, so a `nil` here would be a
        // programmer error (an illegal collection/type), not a recoverable one.
        guard let url = components.url else {
            preconditionFailure("Could not build region URL for \(collection)/\(type)")
        }
        return url
    }

    /// Parse a `region://` URL into its components, or `nil` if it isn't a
    /// well-formed `region://<collection>/<type>` URL.
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
