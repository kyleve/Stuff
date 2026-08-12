import WhereCore

extension WhereTheme {
    var title: String {
        switch self {
            case .standard: String(localized: .themeGlassTitle)
            case .alternate: String(localized: .themeFolioTitle)
        }
    }

    var detail: String {
        switch self {
            case .standard: String(localized: .themeGlassDetail)
            case .alternate: String(localized: .themeFolioDetail)
        }
    }
}
