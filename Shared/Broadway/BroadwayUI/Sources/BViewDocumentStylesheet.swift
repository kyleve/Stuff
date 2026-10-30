import BroadwayCore
import SwiftUI
import UIKit
import ViewDocumentCore
import ViewDocumentUI

/// Resolves document dimensions and decoration policy once per Broadway slice.
public struct BViewDocumentStylesheet: BStylesheet, Sendable {
    public let background: Color
    public let backgrounds: ViewDocumentAppearance.Backgrounds
    public let dimensionScales: [ViewFontDescriptor.TextStyle: Double]
    public let motionIsStatic: Bool
    public let showsDecoration: Bool

    public init(context: SlicingContext) {
        self.init(traits: context.traits)
    }

    public init(traits: BTraits) {
        switch (traits.mode, traits.accessibility.isDarkerSystemColorsEnabled) {
            case (.light, false): backgrounds = Self.lightBackgrounds
            case (.dark, false): backgrounds = Self.darkBackgrounds
            case (.light, true): backgrounds = Self.lightContrastBackgrounds
            case (.dark, true): backgrounds = Self.darkContrastBackgrounds
        }
        background = backgrounds.primary
        var scales: [ViewFontDescriptor.TextStyle: Double] = [:]
        for style in ViewFontDescriptor.TextStyle.allCases {
            scales[style] = Double(BScaledDimension.value(
                1,
                relativeTo: style.uiTextStyle,
                category: traits.contentSizeCategory,
            ))
        }
        dimensionScales = scales
        motionIsStatic = traits.accessibility.isReduceMotionEnabled
        showsDecoration = !traits.accessibility.isReduceTransparencyEnabled && !traits.accessibility
            .isDarkerSystemColorsEnabled
    }

    public static let `default` = Self()

    private init() {
        background = .white
        backgrounds = .init(
            primary: .white,
            secondary: .white,
            grouped: .white,
            secondaryGrouped: .white,
        )
        dimensionScales = [:]
        motionIsStatic = true
        showsDecoration = false
    }

    // Cache the dynamic providers so equal trait slices keep equal Color identities.
    private static let lightBackgrounds = makeBackgrounds(isDark: false, increasedContrast: false)
    private static let darkBackgrounds = makeBackgrounds(isDark: true, increasedContrast: false)
    private static let lightContrastBackgrounds = makeBackgrounds(
        isDark: false,
        increasedContrast: true,
    )
    private static let darkContrastBackgrounds = makeBackgrounds(
        isDark: true,
        increasedContrast: true,
    )

    private enum BackgroundLevel { case primary, secondary, grouped, secondaryGrouped }

    private static func makeBackgrounds(
        isDark: Bool,
        increasedContrast: Bool,
    ) -> ViewDocumentAppearance.Backgrounds {
        func color(_ level: BackgroundLevel) -> Color {
            Color(uiColor: UIColor { hostTraits in
                // Mode and contrast belong to Broadway. Elevation belongs to the actual
                // sheet/popover host and must remain dynamic until the color is drawn.
                let traits = UITraitCollection(traitsFrom: [
                    hostTraits,
                    UITraitCollection(userInterfaceStyle: isDark ? .dark : .light),
                    UITraitCollection(accessibilityContrast: increasedContrast ? .high : .normal),
                ])
                let native: UIColor = switch level {
                    case .primary: .systemBackground
                    case .secondary: .secondarySystemBackground
                    case .grouped: .systemGroupedBackground
                    case .secondaryGrouped: .secondarySystemGroupedBackground
                }
                return native.resolvedColor(with: traits)
            })
        }
        return .init(
            primary: color(.primary),
            secondary: color(.secondary),
            grouped: color(.grouped),
            secondaryGrouped: color(.secondaryGrouped),
        )
    }

    public var appearance: ViewDocumentAppearance {
        .init(backgrounds: backgrounds, dimensionScales: dimensionScales)
    }

    public func shows(_ role: BSurfaceLayerRole) -> Bool {
        switch role {
            case .essential: true
            case .ornament: showsDecoration
        }
    }
}

extension ViewFontDescriptor.TextStyle {
    fileprivate var uiTextStyle: UIFont.TextStyle {
        switch self {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
        }
    }
}
