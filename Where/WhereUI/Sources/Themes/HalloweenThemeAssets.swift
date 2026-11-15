import SwiftUI
import UIKit
import ViewDocumentCore
import ViewDocumentUI

/// Decode bundled illustrations once at the preparation boundary, never from a view body.
@MainActor
enum HalloweenThemeAssets {
    static func load() throws -> ViewDocumentAssets {
        var images: [ViewAssetID: Image] = [:]
        for artwork in Artwork.allCases {
            guard let url = Bundle.module.url(forResource: artwork.resource, withExtension: "png"),
                  let image = UIImage(contentsOfFile: url.path)
            else {
                throw WhereThemeValidationError(
                    path: artwork.resource,
                    reason: "Missing or unreadable theme illustration",
                )
            }
            images[artwork.id] = Image(uiImage: image)
        }
        return .init(images: images, symbols: [:])
    }

    private enum Artwork: CaseIterable {
        case pumpkins, moon, vine
        var id: ViewAssetID {
            switch self {
                case .pumpkins: .init(rawValue: "halloween.pumpkins")
                case .moon: .init(rawValue: "halloween.moon")
                case .vine: .init(rawValue: "halloween.vine")
            }
        }

        var resource: String {
            switch self {
                case .pumpkins: "HalloweenPumpkins"
                case .moon: "HalloweenMoon"
                case .vine: "HalloweenVine"
            }
        }
    }
}
