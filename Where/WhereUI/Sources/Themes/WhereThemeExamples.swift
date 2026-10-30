#if DEBUG
    import Foundation

    /// Development previews use the same bundled document and prepared artwork as the app.
    @MainActor
    enum WhereThemeExamples: String, CaseIterable {
        case halloween = "HalloweenTheme"

        func prepare() throws -> PreparedWhereThemeDocument {
            let documents = try WhereBundledThemes.documents
                .get() + [WhereBundledThemes.load(rawValue)]
            return try WhereThemeCatalog(documents: documents).prepare(
                .halloween,
                assets: HalloweenThemeAssets.load(),
            )
        }
    }
#endif
