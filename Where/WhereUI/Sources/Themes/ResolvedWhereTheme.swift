import BroadwayCore
import ViewDocumentCore

/// Complete authored values. Only a catalog can construct a resolved theme.
public struct ResolvedWhereTheme: Hashable, Sendable {
    public let id: WhereThemeDocument.ID
    public let values: WhereThemeValues
    public let appearance: WhereThemeAppearance
    public let components: WhereThemeComponents
    public let fallback: WhereThemeDocument.Fallback

    init(
        id: WhereThemeDocument.ID,
        values: WhereThemeValues,
        appearance: WhereThemeAppearance,
        components: WhereThemeComponents,
        fallback: WhereThemeDocument.Fallback,
    ) {
        self.id = id; self.values = values; self.appearance = appearance
        self.components = components; self.fallback = fallback
    }
}

extension WhereThemeValues {
    func inheriting(_ parent: Self?) throws -> Self {
        func merged<Value: Identifiable>(
            _ entries: [Value]?,
            _ inherited: [Value]?,
            path: String,
        ) throws -> [Value] where Value.ID: Hashable {
            let entries = entries ?? []
            guard entries.count <= 128, Set(entries.map(\.id)).count == entries.count else {
                throw WhereThemeValidationError(
                    path: path,
                    reason: "Duplicate names or too many named values",
                )
            }
            var result = inherited ?? []
            for value in entries {
                if let index = result
                    .firstIndex(where: { $0.id == value.id }) { result[index] = value }
                else { result.append(value) }
            }
            guard result.count <= 128 else { throw WhereThemeValidationError(
                path: path,
                reason: "Too many inherited values",
            ) }
            return result
        }
        return try .init(
            colors: merged(colors, parent?.colors, path: "values.colors"),
            fonts: merged(fonts, parent?.fonts, path: "values.fonts"),
            surfaces: merged(surfaces, parent?.surfaces, path: "values.surfaces"),
        )
    }

    func color(_ reference: ColorValue.ID) throws -> BThemeValue<ViewColorDescriptor> {
        guard let value = colors?.first(where: { $0.id == reference })?.value else {
            throw WhereThemeValidationError(
                path: "values.colors.\(reference.rawValue)",
                reason: "Missing named color",
            )
        }
        return value
    }

    func font(_ reference: FontValue.ID) throws -> BThemeValue<ViewFontDescriptor> {
        guard let value = fonts?.first(where: { $0.id == reference })?.value else {
            throw WhereThemeValidationError(
                path: "values.fonts.\(reference.rawValue)",
                reason: "Missing named font",
            )
        }
        return value
    }

    func surface(_ reference: SurfaceValue.ID) throws -> BThemeValue<WhereThemeSurface> {
        guard let value = surfaces?.first(where: { $0.id == reference })?.value else {
            throw WhereThemeValidationError(
                path: "values.surfaces.\(reference.rawValue)",
                reason: "Missing named surface",
            )
        }
        func resolve(_ mode: BMode) throws -> WhereThemeSurface {
            switch value.resolve(mode: mode) {
                case .reflective: .reflective
                case let .paper(paper):
                    try .matte(.init(
                        fill: .init(base: color(paper.fill), tintMix: paper.tintMix),
                        outline: .init(opacity: paper.outline.opacity, width: paper.outline.width),
                        shadow: .init(
                            color: color(paper.shadow.color),
                            radius: paper.shadow.radius,
                            offsetY: paper.shadow.offsetY,
                        ),
                        pressedTintOpacity: paper.pressedTintOpacity,
                    ))
            }
        }
        let light = try resolve(.light), dark = try resolve(.dark)
        return light == dark ? .constant(light) : .modes(.init(light: light, dark: dark))
    }
}

extension WhereThemeComponents {
    /// Named surface roles own these fields. Other geometry stays in the typed appearance patch.
    func applyingReferences(
        to authored: WhereThemeAppearance,
        values: WhereThemeValues,
    ) throws -> WhereThemeAppearance {
        var result = authored
        for role in Role.allCases {
            guard let component = self[role] else { continue }
            if case let .value(reference) = component.background {
                let color = try values.color(reference)
                if role == .locations {
                    result.locationsBackground = result.locationsBackground ?? .init()
                    result.locationsBackground?.paper = color
                }
            }
            if case let .value(reference) = component.foreground { _ = try values.color(reference) }
            if case let .value(reference) = component.heading { _ = try values.font(reference) }
            if case let .value(reference) = component.body { _ = try values.font(reference) }
            if case let .value(reference) = component.surface {
                let surface = try values.surface(reference)
                switch role {
                    case .regularCard:
                        if result.card == nil { result.card = .init() }
                        if result.card?.regular == nil { result.card?.regular = .init() }
                        result.card?.regular?.surface = surface
                    case .compactCard:
                        if result.card == nil { result.card = .init() }
                        if result.card?.compact == nil { result.card?.compact = .init() }
                        result.card?.compact?.surface = surface
                    case .elsewhereCard:
                        func paper(_ mode: BMode) throws -> WhereThemeMatteSurface {
                            guard case let .matte(paper) = surface.resolve(mode: mode)
                            else { throw WhereThemeValidationError(
                                path: "components.elsewhereCard.surface",
                                reason: "Elsewhere cards require opaque paper",
                            ) }
                            return paper
                        }
                        if result.card == nil { result.card = .init() }
                        if result.card?
                            .elsewherePaper == nil { result.card?.elsewherePaper = .init() }
                        result.card?.elsewherePaper?.surface = try .modes(.init(
                            light: paper(.light),
                            dark: paper(.dark),
                        ))
                    case .welcome:
                        result.locationWelcome = result.locationWelcome ?? .init(); result
                            .locationWelcome?.surface = surface
                    case .privacy:
                        result.privacyPassportCard = result.privacyPassportCard ?? .init(); result
                            .privacyPassportCard?.surface = surface
                    case .summary:
                        if result.locationForecast == nil { result.locationForecast = .init() }
                        if result.locationForecast?
                            .summary == nil { result.locationForecast?.summary = .init() }
                        result.locationForecast?.summary?.treatment = surface
                    case .locations, .elsewhere, .year, .settings, .sheet, .forecastPanel,
                         .calendarMonth,
                         .timelineEntry, .section: break
                }
            }
        }
        return result
    }
}
