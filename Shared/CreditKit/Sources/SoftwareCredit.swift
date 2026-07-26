import Foundation

/// A third-party work the project uses, with the license it is used under.
///
/// Credits cover two different relationships, which ``Kind`` keeps apart: a
/// ``Kind/library`` is compiled into the shipping binary, while a
/// ``Kind/developmentTool`` is only used to build the project and never reaches
/// a user's device. Both need attribution — permissive licenses ask for the
/// notice to travel with every copy — but conflating them would tell a reader
/// of the About screen something untrue about the app they are running, so the
/// distinction is modeled rather than left to a comment.
///
/// Names, versions, and license titles are proper nouns and legal terms, so
/// they are deliberately **not** localized; the UI supplies the translated
/// framing around them.
public struct SoftwareCredit: Sendable, Hashable, Identifiable, Codable {
    /// How a credited work relates to the shipping app.
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        /// Linked into the app binary — the user is running this code.
        case library
        /// Used to build or develop the app; absent from the shipped bundle.
        case developmentTool
    }

    /// The work's name as its author publishes it.
    public let name: String
    /// Whether this ships in the binary or only builds it.
    public let kind: Kind
    /// The pinned version: a semantic version for a package, a short commit for
    /// a work pinned by revision.
    public let version: String
    /// Where the project lives, for a "learn more" link.
    public let homepageURL: URL?
    /// The license's title, e.g. "MIT License".
    public let licenseName: String
    /// Stem of the vendored license file under `Resources/Licenses/`.
    let licenseResource: String

    public var id: String {
        name
    }

    /// The full license text, or `nil` when the vendored file is missing or
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
        // same defense `CreditCatalog` takes for its manifest).
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

    @_spi(Testing) public init(
        name: String,
        kind: Kind,
        version: String,
        homepageURL: URL?,
        licenseName: String,
        licenseResource: String,
    ) {
        self.name = name
        self.kind = kind
        self.version = version
        self.homepageURL = homepageURL
        self.licenseName = licenseName
        self.licenseResource = licenseResource
    }

    private static let logger = CreditLog.softwareCredit
}
