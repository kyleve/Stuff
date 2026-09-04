import WhereCore

extension WhereTheme {
    var title: String {
        switch self {
            case .standard: String(localized: .themeStandardTitle)
            case .alternate: String(localized: .themeAlternateTitle)
        }
    }

    var detail: String {
        switch self {
            case .standard: String(localized: .themeStandardDetail)
            case .alternate: String(localized: .themeAlternateDetail)
        }
    }
}
