import Foundation

/// A third-party library the app links, with the license text it ships under.
///
/// WhereCore owns this because WhereCore is what pulls the dependencies in —
/// today only ZIPFoundation, for backup archives. The names, versions, and
/// license titles are proper nouns and legal terms, so they are deliberately
/// **not** localized; the UI supplies the translated framing around them.
///
/// The list is hand-maintained against the root `Package.swift` /
/// `Package.resolved`, because a running app can't read either. Adding an
/// external package means adding a credit here and vendoring its license text —
/// see [`WhereCore/AGENTS.md`](../../AGENTS.md).
public struct SoftwareCredit: Sendable, Hashable, Identifiable {
    /// The package's name as it appears in `Package.swift`.
    public let name: String
    /// The resolved version in `Package.resolved`.
    public let version: String
    /// Where the project lives, for a "learn more" link.
    public let homepageURL: URL?
    /// The license's title, e.g. "MIT License".
    public let licenseName: String
    /// Stem of the vendored license file under `Resources/Licenses/`.
    private let licenseResource: String

    public var id: String {
        name
    }

    /// Every third-party library linked into the app.
    public static let all: [SoftwareCredit] = [
        SoftwareCredit(
            name: "ZIPFoundation",
            version: "0.9.20",
            homepageURL: URL(string: "https://github.com/weichsel/ZIPFoundation"),
            licenseName: "MIT License",
            licenseResource: "ZIPFoundation",
        ),
    ]

    /// The full license text, or `nil` when the bundled file is missing or
    /// unreadable.
    ///
    /// MIT and most permissive licenses require shipping the notice verbatim, so
    /// a missing file is a real defect rather than a cosmetic one: it fault-logs
    /// and trips an `assertionFailure` in debug, and returns `nil` in release so
    /// the caller can say the text is unavailable instead of rendering a blank
    /// screen that reads like a license with no terms.
    public func licenseText() -> String? {
        // `.process("Resources")` preserves the `Licenses/` subdirectory, but
        // fall back to a top-level lookup in case a bundler flattens it (the
        // same defense `RegionCatalog` takes for its `regions/` folder).
        let url = Bundle.module.url(
            forResource: licenseResource,
            withExtension: "txt",
            subdirectory: "Licenses",
        ) ?? Bundle.module.url(forResource: licenseResource, withExtension: "txt")

        guard let url else {
            Self.logger { .missingLicense(credit: name, resource: licenseResource) }
            assertionFailure("Missing bundled license text for \(name)")
            return nil
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logger(attachments: [.error(error, name: "read-error")]) {
                .unreadableLicense(credit: name, description: error.localizedDescription)
            }
            assertionFailure("Failed to read bundled license text for \(name): \(error)")
            return nil
        }
    }

    private static let logger = WhereLog.root(SoftwareCreditLog.self)
}
