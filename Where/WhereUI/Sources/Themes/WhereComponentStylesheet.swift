import BroadwayCore
import BroadwayUI
import SwiftUI
import UIKit
import ViewDocumentCore
import ViewDocumentUI
import WhereCore

/// Typed component roles resolve named references and accessibility policy before view
/// construction.
struct WhereComponentStylesheet: BStylesheet {
    struct Style: Equatable {
        var background: Color?
        var foreground: Color?
        var secondaryForeground: Color?
        var heading: Font?
        var body: Font?
        var bodyDesign: Font.Design?
        var surface: WhereStylesheet.SurfaceTreatment?
        var nativeArtwork: Set<WhereThemeNativeArtwork> = []
        var artworkOpacity: [WhereThemeArtwork.ID: Double] = [:]
        var outsets = EdgeInsets()
    }

    private var styles: [WhereThemeComponents.Role: Style] = [:]
    subscript(role: WhereThemeComponents.Role) -> Style {
        styles[role] ?? .init()
    }

    init(context: SlicingContext) throws {
        let resolved = try context.themes[WhereDocumentTheme.self].document?.resolved
            ?? WhereBundledThemeDefinitions.resolved(context.themes[WhereTheme.self])
        try self.init(resolved: resolved, traits: context.traits)
    }

    private init(resolved: ResolvedWhereTheme, traits: BTraits) throws {
        let policy = BViewDocumentStylesheet(traits: traits)
        for role in WhereThemeComponents.Role.allCases {
            guard let component = resolved.components[role] else { continue }
            var style = Style()
            if case let .value(reference) = component
                .background
            {
                let color = try resolved.values.color(reference).resolve(mode: traits.mode)
                style.background = traits.accessibility
                    .isReduceTransparencyEnabled && !WhereThemeValidation.isOpaque(color)
                    ? policy.background : policy.appearance.color(color)
            }
            if case let .value(reference) = component
                .foreground
            {
                style.foreground = try policy.appearance
                    .color(resolved.values.color(reference).resolve(mode: traits.mode))
                style.secondaryForeground = style.foreground?.opacity(
                    traits.accessibility.isDarkerSystemColorsEnabled ? 1 : 0.85,
                )
            }
            if case let .value(reference) = component
                .heading
            {
                style.heading = try Self.nativeFont(
                    resolved.values.font(reference).resolve(mode: traits.mode),
                    relativeTo: .headline,
                    traits: traits,
                )
            }
            if case let .value(reference) = component
                .body
            {
                let font = try resolved.values.font(reference).resolve(mode: traits.mode)
                style.body = Self.nativeFont(font, relativeTo: .body, traits: traits)
                style.bodyDesign = font.design?.fontDesign
            }
            if case let .value(reference) = component
                .surface
            {
                style.surface = try resolved.values.surface(reference).resolve(mode: traits.mode)
                    .resolve(
                        mode: traits.mode,
                        appearance: policy.appearance,
                        base: .reflective,
                    )
            }
            if var surface = style.surface {
                if traits.accessibility.isReduceTransparencyEnabled, case .reflective = surface {
                    surface = .matte(.init(
                        fill: .init(base: policy.background, tintMix: 0),
                        outline: .init(opacity: 0, width: 0),
                        shadow: .init(color: .clear, radius: 0, offsetY: 0),
                        pressedTintOpacity: 0,
                    ))
                }
                if traits.accessibility.isDarkerSystemColorsEnabled,
                   case var .matte(paper) = surface
                {
                    paper.outline.opacity = max(0.65, paper.outline.opacity)
                    paper.outline.width = max(1.5, paper.outline.width)
                    surface = .matte(paper)
                }
                style.surface = surface
            }
            style.nativeArtwork = Set(component.nativeArtwork ?? [])
            for artwork in component.artwork ?? [] where policy.shows(artwork.role) {
                style.artworkOpacity[artwork.id] = artwork.opacity.resolve(mode: traits.mode)
                let outsets = artwork.placement.outsets
                style.outsets.top = max(style.outsets.top, outsets.top)
                style.outsets.leading = max(style.outsets.leading, outsets.leading)
                style.outsets.bottom = max(style.outsets.bottom, outsets.bottom)
                style.outsets.trailing = max(style.outsets.trailing, outsets.trailing)
            }
            // Limit gutters before reducing the space available to native labels and controls.
            // Artwork uses the same allowance to scale its size, offset, and paint bounds together.
            style.outsets.leading = min(24, style.outsets.leading)
            style.outsets.trailing = min(24, style.outsets.trailing)
            styles[role] = style
        }
    }

    private static func nativeFont(
        _ descriptor: ViewFontDescriptor,
        relativeTo textStyle: UIFont.TextStyle,
        traits: BTraits,
    ) -> Font {
        var descriptor = descriptor
        if case let .fixed(points) = descriptor.size {
            // A point size defines the normal-size baseline for native text. Decorative
            // ViewDocument text retains its independent fixed-size contract.
            descriptor.size = .fixed(BScaledDimension.value(
                points,
                relativeTo: textStyle,
                category: traits.contentSizeCategory,
            ))
        }
        return descriptor.font
    }

    private init() {}
    static let `default`: Self = {
        do { return try Self(
            resolved: WhereBundledThemeDefinitions.resolved(.standard),
            traits: BTraits(),
        ) } catch { WhereBundledThemeDefinitions.reportPackagingFailure(error); return Self() }
    }()
}

extension EnvironmentValues {
    var whereComponentStylesheet: WhereComponentStylesheet {
        bContext.stylesheet(
            WhereComponentStylesheet.self,
            fallback: .default,
        )
    }
}
