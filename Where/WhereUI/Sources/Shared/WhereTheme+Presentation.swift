import WhereCore

extension WhereTheme {
    var title: String {
        switch self {
            case .standard: String(localized: .themeStandardTitle)
            case .alternate: String(localized: .themeAlternateTitle)
            case .halloween: String(localized: .themeHalloweenTitle)
            case .holiday: String(localized: .themeHolidayTitle)
        }
    }

    var detail: String {
        switch self {
            case .standard: String(localized: .themeStandardDetail)
            case .alternate: String(localized: .themeAlternateDetail)
            case .halloween: String(localized: .themeHalloweenDetail)
            case .holiday: String(localized: .themeHolidayDetail)
        }
    }
}
