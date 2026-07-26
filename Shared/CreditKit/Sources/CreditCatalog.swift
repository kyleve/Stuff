import Foundation

/// Every third-party work the project credits, loaded once from the bundled
/// `credits.json` manifest.
///
/// The manifest is **generated**, not hand-written: `Tools/generate-credits.rb`
/// derives it from the root `Package.swift` / `Package.resolved` (for linked
/// libraries) and `.agents/external-skills.json` (for development tools), and
/// vendors each license notice beside it. A running app can read neither of
/// those files, which is why the answer is baked into a resource at build time.
///
/// Deriving the list rather than maintaining it by hand is what keeps it honest
/// as the dependency graph changes: a package linked by *any* module shows up
/// the next time the script runs, so a credit is not something a module has to
/// remember to vend.
public struct CreditCatalog: Sendable {
    /// Every credit, in manifest order.
    public let credits: [SoftwareCredit]

    /// The process-wide catalog, decoded from the bundle on first use.
    public static let shared: CreditCatalog = .loadFromBundle()

    @_spi(Testing) public init(credits: [SoftwareCredit]) {
        self.credits = credits
    }

    /// The credits of one kind, in manifest order.
    public func credits(ofKind kind: SoftwareCredit.Kind) -> [SoftwareCredit] {
        credits.filter { $0.kind == kind }
    }
}

extension CreditCatalog {
    private static let logger = CreditLog.catalog

    @_spi(Testing) public static func decode(from data: Data) throws -> CreditCatalog {
        try CreditCatalog(credits: JSONDecoder().decode([SoftwareCredit].self, from: data))
    }

    private static func loadFromBundle() -> CreditCatalog {
        guard let url = Bundle.module.url(forResource: "credits", withExtension: "json") else {
            logger { .missingManifest }
            assertionFailure("Missing bundled credits.json")
            return CreditCatalog(credits: [])
        }
        do {
            let catalog = try decode(from: Data(contentsOf: url))
            logger { .loaded(creditCount: catalog.credits.count) }
            return catalog
        } catch {
            logger(attachments: [.error(error, name: "decode-error")]) {
                .decodeFailed(description: error.localizedDescription)
            }
            assertionFailure("Failed to decode bundled credits.json: \(error)")
            return CreditCatalog(credits: [])
        }
    }
}
