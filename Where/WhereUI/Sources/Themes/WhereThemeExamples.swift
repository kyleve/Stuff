#if DEBUG
    import Foundation
    import SFSafeSymbols
    import SwiftUI
    import ViewDocumentCore
    import ViewDocumentUI

    /// Bundled wire-format examples used by previews and integration tests.
    @MainActor
    enum WhereThemeExamples: String, CaseIterable {
        case halloween = "HalloweenTheme"
        case christmas = "ChristmasTheme"

        static var assets: ViewDocumentAssets {
            .init(
                images: [:],
                symbols: [.init(rawValue: "seasonal.bell"): Image(systemSymbol: .bellFill)],
            )
        }

        func prepare() throws -> PreparedWhereThemeDocument {
            guard let url = Bundle.module.url(forResource: rawValue, withExtension: "json") else {
                throw WhereThemeValidationError(
                    path: rawValue,
                    reason: "Missing bundled theme fixture",
                )
            }
            let assets = Self.assets
            let validated = try ValidatedWhereThemeDocument.decode(
                Data(contentsOf: url),
                resources: assets.resources,
            )
            return try PreparedWhereThemeDocument(validated: validated, assets: assets)
        }
    }
#endif
