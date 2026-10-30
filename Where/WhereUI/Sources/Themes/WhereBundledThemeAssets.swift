import SwiftUI
import UIKit
import ViewDocumentCore
import ViewDocumentUI

/// Decode bundled illustrations once at the preparation boundary, never from a view body.
@MainActor
enum WhereBundledThemeAssets {
    static func load(illustrations: [ViewAssetID: String]) throws -> ViewDocumentAssets {
        var images: [ViewAssetID: Image] = [:]
        for (assetID, resource) in illustrations {
            guard let url = Bundle.module.url(forResource: resource, withExtension: "png"),
                  let image = UIImage(contentsOfFile: url.path)
            else {
                throw WhereThemeValidationError(
                    path: resource,
                    reason: "Missing or unreadable theme illustration",
                )
            }
            images[assetID] = Image(uiImage: image)
        }
        return .init(images: images, symbols: [:])
    }
}
