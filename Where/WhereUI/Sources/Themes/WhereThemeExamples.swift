#if DEBUG
    import Foundation
    import WhereCore

    /// Snapshot specimens use the app's bundled theme preparation path.
    @MainActor
    enum WhereThemeExamples: String, CaseIterable {
        case halloween = "HalloweenTheme"
        case holiday = "HolidayTheme"

        var theme: WhereTheme {
            switch self {
                case .halloween: .halloween
                case .holiday: .holiday
            }
        }

        func prepare() throws -> PreparedWhereThemeDocument {
            try WhereBundledThemes.prepared(theme)
        }
    }
#endif
