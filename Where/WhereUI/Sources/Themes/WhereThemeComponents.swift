/// Sparse component definitions. Omission inherits; clear removes an optional visual part.
public struct WhereThemeComponent: Codable, Hashable, Sendable, WhereThemePatch {
    public var surface: WhereThemeOptional<WhereThemeValues.SurfaceValue.ID>?
    public var background: WhereThemeOptional<WhereThemeValues.ColorValue.ID>?
    public var foreground: WhereThemeOptional<WhereThemeValues.ColorValue.ID>?
    public var heading: WhereThemeOptional<WhereThemeValues.FontValue.ID>?
    public var body: WhereThemeOptional<WhereThemeValues.FontValue.ID>?
    public var nativeArtwork: [WhereThemeNativeArtwork]?
    public var artwork: [WhereThemeArtwork]?

    public init() {}

    func inheriting(_ parent: Self?) -> Self {
        var result = self
        result.surface = surface ?? parent?.surface
        result.background = background ?? parent?.background
        result.foreground = foreground ?? parent?.foreground
        result.heading = heading ?? parent?.heading
        result.body = body ?? parent?.body
        result.nativeArtwork = nativeArtwork ?? parent?.nativeArtwork
        result.artwork = artwork ?? parent?.artwork
        return result
    }
}

/// Component identity is a finite, typed contract between the document and native Where views.
public struct WhereThemeComponents: Codable, Hashable, Sendable, WhereThemePatch {
    public enum Role: String, Codable, CaseIterable, Hashable, Sendable {
        case locations, elsewhere, year, settings, sheet
        case regularCard, compactCard, elsewhereCard, summary, forecastPanel
        case calendarMonth, timelineEntry, section, welcome, privacy
    }

    public var locations: WhereThemeComponent?
    public var elsewhere: WhereThemeComponent?
    public var year: WhereThemeComponent?
    public var settings: WhereThemeComponent?
    public var sheet: WhereThemeComponent?
    public var regularCard: WhereThemeComponent?
    public var compactCard: WhereThemeComponent?
    public var elsewhereCard: WhereThemeComponent?
    public var summary: WhereThemeComponent?
    public var forecastPanel: WhereThemeComponent?
    public var calendarMonth: WhereThemeComponent?
    public var timelineEntry: WhereThemeComponent?
    public var section: WhereThemeComponent?
    public var welcome: WhereThemeComponent?
    public var privacy: WhereThemeComponent?

    public init() {}

    public subscript(role: Role) -> WhereThemeComponent? {
        get {
            switch role {
                case .locations: locations
                case .elsewhere: elsewhere
                case .year: year
                case .settings: settings
                case .sheet: sheet
                case .regularCard: regularCard
                case .compactCard: compactCard
                case .elsewhereCard: elsewhereCard
                case .summary: summary
                case .forecastPanel: forecastPanel
                case .calendarMonth: calendarMonth
                case .timelineEntry: timelineEntry
                case .section: section
                case .welcome: welcome
                case .privacy: privacy
            }
        }
        set {
            switch role {
                case .locations: locations = newValue
                case .elsewhere: elsewhere = newValue
                case .year: year = newValue
                case .settings: settings = newValue
                case .sheet: sheet = newValue
                case .regularCard: regularCard = newValue
                case .compactCard: compactCard = newValue
                case .elsewhereCard: elsewhereCard = newValue
                case .summary: summary = newValue
                case .forecastPanel: forecastPanel = newValue
                case .calendarMonth: calendarMonth = newValue
                case .timelineEntry: timelineEntry = newValue
                case .section: section = newValue
                case .welcome: welcome = newValue
                case .privacy: privacy = newValue
            }
        }
    }

    func inheriting(_ parent: Self?) -> Self {
        var result = Self()
        for role in Role
            .allCases
        {
            result[role] = (self[role] ?? .init()).inheriting(parent?[role])
        }
        return result
    }
}

extension WhereThemeComponents {
    /// A direct value replaces an inherited reference. A document cannot author both for one field.
    func assigningLiteralOwnership(_ appearance: WhereThemeAppearance) throws -> Self {
        var result = self
        func literalSurface(_ present: Bool, role: Role) throws {
            guard present else { return }
            var component = result[role] ?? .init()
            if case .value = component.surface {
                throw WhereThemeValidationError(
                    path: "components.\(role).surface",
                    reason: "Choose a named reference or a literal surface",
                )
            }
            component.surface = .clear
            result[role] = component
        }
        try literalSurface(appearance.card?.regular?.surface != nil, role: .regularCard)
        try literalSurface(appearance.card?.compact?.surface != nil, role: .compactCard)
        try literalSurface(appearance.card?.elsewherePaper?.surface != nil, role: .elsewhereCard)
        try literalSurface(appearance.locationWelcome?.surface != nil, role: .welcome)
        try literalSurface(appearance.privacyPassportCard?.surface != nil, role: .privacy)
        try literalSurface(appearance.locationForecast?.summary?.treatment != nil, role: .summary)
        if appearance.locationsBackground?.paper != nil {
            var component = result.locations ?? .init()
            if case .value = component.background {
                throw WhereThemeValidationError(
                    path: "components.locations.background",
                    reason: "Choose a named reference or a literal background",
                )
            }
            component.background = .clear
            result.locations = component
        }
        return result
    }
}
