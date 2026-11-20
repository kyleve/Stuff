import Foundation

/// Asset availability is checked before a document reaches the renderer.
public struct ViewDocumentResources: Hashable, Sendable {
    public let images: Set<ViewAssetID>
    public let symbols: Set<ViewSymbolID>

    public init(images: Set<ViewAssetID>, symbols: Set<ViewSymbolID>) {
        self.images = images
        self.symbols = symbols
    }
}
