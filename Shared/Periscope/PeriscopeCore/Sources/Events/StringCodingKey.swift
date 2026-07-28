import Foundation

/// A `CodingKey` built from a bare string — what a string-backed identifier
/// (`AmbientKind`, `LogSessionAttributeKey`) hands back from
/// `CodingKeyRepresentable` so dictionaries keyed by it encode as JSON
/// objects instead of the flat alternating key/value array a dictionary with
/// non-string keys falls back to.
struct StringCodingKey: CodingKey {
    let stringValue: String

    var intValue: Int? {
        nil
    }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
