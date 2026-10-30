import ViewDocumentUI

/// Prepared resources are injected once at a Where root, independently of cached appearance values.
public struct PreparedWhereThemeDocument {
    public let validated: ValidatedWhereThemeDocument
    let layers: [WhereThemeDocument.Slot: [PreparedViewDocument]]
    public init(validated: ValidatedWhereThemeDocument, assets: ViewDocumentAssets) throws {
        self.validated = validated
        var prepared: [WhereThemeDocument.Slot: [PreparedViewDocument]] = [:]
        for (slot, documents) in validated.layers {
            prepared[slot] = try documents.map { try PreparedViewDocument(
                document: $0,
                assets: assets,
            ) }
        }
        layers = prepared
    }
}
