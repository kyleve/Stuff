import WhereCore

extension WhereTheme {
    var title: String {
        switch self {
            case .standard: String(localized: .themeStandardTitle)
            case .alternate: String(localized: .themeAlternateTitle)
            case .halloween: String(localized: .themeHalloweenTitle)
        }
    }

    var detail: String {
        switch self {
            case .standard: String(localized: .themeStandardDetail)
            case .alternate: String(localized: .themeAlternateDetail)
            case .halloween: String(localized: .themeHalloweenDetail)
        }
    }
}
