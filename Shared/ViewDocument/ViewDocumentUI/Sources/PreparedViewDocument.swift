import ViewDocumentCore

/// Pairs immutable validated content with its resources before entering a view body.
public struct PreparedViewDocument {
    public let document: ValidatedViewDocument
    let assets: ViewDocumentAssets

    public init(document: ValidatedViewDocument, assets: ViewDocumentAssets) throws {
        guard document.resources.images.isSubset(of: assets.resources.images),
              document.resources.symbols.isSubset(of: assets.resources.symbols)
        else { throw ViewDocumentView.ResourceError.mismatchedAssets }
        self.document = document
        self.assets = assets
    }
}
