#if DEBUG
    import Foundation

    /// Snapshot specimens use the app's bundled theme preparation path.
    @MainActor
    enum WhereThemeExamples: String, CaseIterable {
        case halloween = "HalloweenTheme"

        func prepare() throws -> PreparedWhereThemeDocument {
            try WhereBundledThemes.prepared(.halloween)
        }
    }
#endif
