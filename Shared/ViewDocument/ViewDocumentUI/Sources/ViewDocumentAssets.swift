import SwiftUI
import ViewDocumentCore

/// Prepared images and approved symbols. No file or network work occurs during rendering.
public struct ViewDocumentAssets {
    let images: [ViewAssetID: Image]
    let symbols: [ViewSymbolID: Image]

    public init(images: [ViewAssetID: Image], symbols: [ViewSymbolID: Image]) {
        self.images = images
        self.symbols = symbols
    }

    public var resources: ViewDocumentResources {
        .init(images: Set(images.keys), symbols: Set(symbols.keys))
    }
}
