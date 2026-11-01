import BroadwayUI
import ViewDocumentUI

/// Prepared resources are injected once at a Where root, independently of cached appearance values.
public struct PreparedWhereThemeDocument {
    struct Artwork: Identifiable {
        let id: WhereThemeArtwork.ID
        let placement: BArtworkPlacement
        let role: BSurfaceLayerRole
        let document: PreparedViewDocument
    }

    let componentArtwork: [WhereThemeComponents.Role: [Artwork]]
    public let validated: ValidatedWhereThemeDocument
    public var resolved: ResolvedWhereTheme {
        validated.resolved
    }

    public init(validated: ValidatedWhereThemeDocument, assets: ViewDocumentAssets) throws {
        self.validated = validated
        var artworkByRole: [WhereThemeComponents.Role: [Artwork]] = [:]
        for role in WhereThemeComponents.Role.allCases {
            let entries = validated.resolved.components[role]?.artwork ?? []
            let documents = validated.artwork[role] ?? []
            guard entries.count == documents.count else { throw WhereThemeValidationError(
                path: "artwork",
                reason: "Prepared artwork does not match its definition",
            ) }
            artworkByRole[role] = try zip(entries, documents).map { entry, document in
                try Artwork(
                    id: entry.id,
                    placement: BArtworkPlacement(entry.placement),
                    role: entry.role,
                    document: PreparedViewDocument(document: document, assets: assets),
                )
            }
        }
        componentArtwork = artworkByRole
    }
}
