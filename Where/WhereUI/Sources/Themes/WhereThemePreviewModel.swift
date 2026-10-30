import Foundation
import Observation
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

/// Session-only preview state. The app injects this only for its Development audience.
@MainActor
@Observable
public final class WhereThemePreviewModel {
    public private(set) var theme: PreparedWhereThemeDocument?
    public private(set) var failure: (any Error)?
    private var catalog: WhereThemeCatalog
    private let assets: ViewDocumentAssets

    public init(catalog: WhereThemeCatalog, assets: ViewDocumentAssets) {
        self.catalog = catalog
        self.assets = assets
    }

    public func select(_ id: WhereThemeDocument.ID) {
        do {
            let prepared = try catalog.prepare(id, assets: assets)
            theme = prepared
            failure = nil
        } catch { failure = error }
    }

    /// Only a completely prepared import replaces the accepted theme and catalog.
    public func importTheme(_ data: Data) {
        do {
            guard data.count <= ViewDocumentLimits.standard.bytes
            else { throw WhereThemeValidationError(
                path: "$",
                reason: "Theme exceeds byte limit",
            ) }
            let document = try JSONDecoder().decode(WhereThemeDocument.self, from: data)
            let replacement = try catalog.replacing(document)
            let prepared = try replacement.prepare(document.id, assets: assets)
            catalog = replacement
            theme = prepared
            failure = nil
        } catch { failure = error }
    }

    public func clear() {
        theme = nil; failure = nil
    }

    public static func bundledOrFallback() -> WhereThemePreviewModel? {
        do { return try bundled() }
        catch { WhereBundledThemeDefinitions.reportPackagingFailure(error); return nil }
    }

    public static func bundled() throws -> WhereThemePreviewModel {
        let documents = try WhereBundledThemes.documents
            .get() + [WhereBundledThemes.load("HalloweenTheme")]
        return try .init(catalog: .init(documents: documents), assets: HalloweenThemeAssets.load())
    }
}

extension EnvironmentValues {
    @Entry var whereThemePreview: WhereThemePreviewModel?
}

extension View {
    /// The app composition root injects this only for the Development audience.
    public func whereThemePreview(_ model: WhereThemePreviewModel?) -> some View {
        environment(\.whereThemePreview, model)
    }
}
