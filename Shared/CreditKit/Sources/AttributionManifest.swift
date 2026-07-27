import Foundation

/// A generated attribution report for one app: every third-party work it is
/// built with, each carrying its own license notice.
///
/// A manifest is **produced by tooling and read at runtime**, never assembled
/// by hand. `Tools/generate-attribution.rb` runs a report over an app's
/// declared sources — its Swift package graph, the agent skills the repository
/// vendors — and writes the result into that app's own resources, which is
/// where it belongs: the report describes one app's dependency graph, so it is
/// the app's data rather than this module's.
///
/// Deriving it is what keeps it honest. A hand-kept list silently goes stale
/// the moment some *other* module adds a dependency, whereas a report re-run
/// picks that up wherever it landed.
public struct AttributionManifest: Sendable, Hashable, Codable {
    /// Every credit, in the order the report generated them.
    public let credits: [SoftwareCredit]

    public init(credits: [SoftwareCredit]) {
        self.credits = credits
    }

    /// The credits of one kind, in report order.
    public func credits(ofKind kind: SoftwareCredit.Kind) -> [SoftwareCredit] {
        credits.filter { $0.kind == kind }
    }
}

extension AttributionManifest {
    /// Decodes a manifest from the JSON a report wrote.
    public static func decode(from data: Data) throws -> AttributionManifest {
        try JSONDecoder().decode(AttributionManifest.self, from: data)
    }

    /// Loads the report `resource`.json from `bundle`.
    ///
    /// Throws rather than logging: CreditKit has no opinion about how a missing
    /// report should be reported, and an app knows things this module can't —
    /// notably that some of its bundles (a developer tool, a test host) are
    /// *expected* to carry no report, while a malformed one is always a defect.
    public static func load(
        from bundle: Bundle,
        resource: String,
    ) throws -> AttributionManifest {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw AttributionError.reportMissing(resource: resource)
        }
        return try decode(from: Data(contentsOf: url))
    }
}

/// A failure loading an attribution report. Decoding failures surface as
/// `DecodingError` from the underlying decoder rather than being wrapped, so a
/// caller keeps the coding path that names the bad field.
public enum AttributionError: Error, Hashable {
    /// The bundle carries no report under that resource name.
    case reportMissing(resource: String)
}
