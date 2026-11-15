import BroadwayCore
import ViewDocumentCore

/// Freezes version 1's implicit defaults when an import enables a previously absent visual part.
/// Version 2 definitions must supply those values themselves or inherit them from a parent.
enum WhereThemeLegacyConversion {
    static func appearance(
        _ patch: WhereThemeAppearance,
        fallback: WhereThemeDocument.Fallback,
    ) throws -> WhereThemeAppearance {
        let base = try WhereBundledThemeDefinitions.resolved(fallback.theme).appearance
        let standard = try WhereBundledThemeDefinitions.resolved(.standard).appearance
        var result = patch
        result.card?.regular = card(
            patch.card?.regular,
            base: base.card?.regular,
            standard: standard,
        )
        result.card?.compact = card(
            patch.card?.compact,
            base: base.card?.compact,
            standard: standard,
        )
        result.locationWelcome?.surface = surface(
            patch.locationWelcome?.surface,
            base: base.locationWelcome?.surface,
        )
        result.locationWelcome?.close?.surface = surface(
            patch.locationWelcome?.close?.surface,
            base: base.locationWelcome?.close?.surface,
        )
        result.privacyPassportCard?.surface = surface(
            patch.privacyPassportCard?.surface,
            base: base.privacyPassportCard?.surface,
        )
        result.locationForecast?.summary?.treatment = surface(
            patch.locationForecast?.summary?.treatment,
            base: base.locationForecast?.summary?.treatment,
        )
        return result
    }

    private static func surface(
        _ patch: BThemeValue<WhereThemeSurface>?,
        base: BThemeValue<WhereThemeSurface>?,
    ) -> BThemeValue<WhereThemeSurface>? {
        guard let patch else { return nil }
        func resolve(_ mode: BMode) -> WhereThemeSurface {
            switch patch.resolve(mode: mode) {
                case .reflective: return .reflective
                case let .matte(value):
                    let inherited: WhereThemeMatteSurface = if case let .matte(existing) = base?
                        .resolve(mode: mode) { existing }
                    else { neutralPaper }
                    return .matte(value.inheriting(inherited))
            }
        }
        return .modes(.init(light: resolve(.light), dark: resolve(.dark)))
    }

    private static var neutralPaper: WhereThemeMatteSurface {
        .init(
            fill: .init(base: .constant(.semantic(.background)), tintMix: 0),
            outline: .init(opacity: 0, width: 0),
            shadow: .init(
                color: .constant(.rgba(red: 0, green: 0, blue: 0, alpha: 0)),
                radius: 0,
                offsetY: 0,
            ),
            pressedTintOpacity: 0,
        )
    }

    private static func card(
        _ patch: WhereThemeAppearance.CardStyle?,
        base: WhereThemeAppearance.CardStyle?,
        standard: WhereThemeAppearance,
    ) -> WhereThemeAppearance.CardStyle? {
        guard var result = patch else { return nil }
        result.surface = surface(result.surface, base: base?.surface)
        if case let .value(paper) = result.paper {
            var inherited: WhereThemeAppearance.CardStyle.Paper?
            if case let .value(value) = base?.paper { inherited = value }
            else if var value = standard.card?.elsewherePaper {
                value.surface = value.surface.map {
                    var paper = $0.resolve(mode: .light)
                    let fill = paper.fill?.base
                        .map { BThemeValue.constant($0.resolve(mode: .light)) }
                    let shadow = paper.shadow?.color
                        .map { BThemeValue.constant($0.resolve(mode: .light)) }
                    paper.fill?.base = fill
                    paper.shadow?.color = shadow
                    return .constant(paper)
                }
                value.contentTint = value.contentTint.map {
                    var tint = $0.resolve(mode: .light)
                    tint.color = tint.color.map { .constant($0.resolve(mode: .light)) }
                    return .constant(tint)
                }
                inherited = value
            }
            result.paper = .value(paper.inheriting(inherited))
        }
        if case let .value(arc) = result.entryStamp?.arc {
            let inherited: WhereThemeAppearance.CardStyle.EntryStamp
                .Arc? = if case let .value(value) = base?.entryStamp?.arc { value }
            else if case let .value(value) = standard.card?.regular?.entryStamp?.arc { value }
            else { nil }
            result.entryStamp?.arc = .value(arc.inheriting(inherited))
        }
        if case let .value(region) = result.regionShape {
            let inherited: WhereThemeAppearance.CardStyle
                .RegionShape? = if case let .value(value) = base?.regionShape { value }
            else if case let .value(value) = standard.card?.regular?.regionShape { value }
            else { nil }
            var value = region.inheriting(inherited)
            value.watermark = artwork(value.watermark)
            value.stamp = artwork(value.stamp)
            result.regionShape = .value(value)
        }
        return result
    }

    private static func artwork(_ patch: WhereThemeAppearance.CardStyle.RegionShape
        .Artwork?) -> WhereThemeAppearance.CardStyle.RegionShape.Artwork?
    {
        guard var result = patch else { return nil }
        if case var .value(stroke) = result.stroke {
            stroke.opacity = stroke.opacity ?? .constant(0.28)
            stroke.width = stroke.width ?? .constant(1.5)
            result.stroke = .value(stroke)
        }
        return result
    }
}
