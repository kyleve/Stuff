import Foundation
import SFSafeSymbols
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

/// Original version 1 payloads remain test resources after their app demonstrations retire.
@MainActor
enum LegacyThemeFixtures {
    enum Theme: String,
        CaseIterable { case halloween = "HalloweenTheme-v1", christmas = "ChristmasTheme-v1" }
    private final class BundleToken {}
    static func document(_ theme: Theme) throws -> WhereThemeDocument {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: theme.rawValue,
            withExtension: "json",
        ) else {
            throw WhereThemeValidationError(
                path: theme.rawValue,
                reason: "Missing version 1 fixture",
            )
        }
        return try JSONDecoder().decode(WhereThemeDocument.self, from: Data(contentsOf: url))
    }

    static func prepare(_ theme: Theme) throws -> PreparedWhereThemeDocument {
        let assets = ViewDocumentAssets(
            images: [:],
            symbols: [.init(rawValue: "seasonal.bell"): Image(systemSymbol: .bellFill)],
        )
        return try PreparedWhereThemeDocument(
            validated: .init(document: document(theme), resources: assets.resources),
            assets: assets,
        )
    }
}
