import Foundation

/// A third-party work an app is built with, and the license it is used under.
///
/// Credits cover two different relationships, which ``Kind`` keeps apart: a
/// ``Kind/library`` is compiled into the shipping binary, while a
/// ``Kind/developmentTool`` is only used to build the project and never reaches
/// a user's device. Both need attribution — permissive licenses ask for the
/// notice to travel with every copy — but conflating them would tell a reader
/// something untrue about the app they are running, so the distinction is
/// modeled rather than left to a comment.
///
/// Names, versions, and license titles are proper nouns and legal terms, so
/// they are deliberately **not** localized; a UI supplies the translated
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
    /// The license, carrying its own notice text.
    public let license: LicenseNotice

    public var id: String {
        name
    }

    public init(
        name: String,
        kind: Kind,
        version: String,
        homepageURL: URL?,
        license: LicenseNotice,
    ) {
        self.name = name
        self.kind = kind
        self.version = version
        self.homepageURL = homepageURL
        self.license = license
    }
}

/// A license and the notice that has to travel with it.
///
/// The text is carried inline rather than referenced by filename so a manifest
/// is self-contained: one decode yields everything needed to discharge the
/// attribution, with no second lookup that can come back empty. Permissive
/// licenses require the notice verbatim, which is why it is stored rather than
/// summarized or reflowed.
public struct LicenseNotice: Sendable, Hashable, Codable {
    /// The license's title, e.g. "MIT License".
    public let name: String
    /// The full notice, verbatim.
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}
