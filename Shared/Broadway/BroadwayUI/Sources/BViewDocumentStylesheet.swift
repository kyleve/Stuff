import BroadwayCore
import SwiftUI
import UIKit
import ViewDocumentCore
import ViewDocumentUI

/// Resolves document dimensions and decoration policy once per Broadway slice.
public struct BViewDocumentStylesheet: BStylesheet, Sendable {
    public let background: Color
    public let dimensionScales: [ViewFontDescriptor.TextStyle: Double]
    public let motionIsStatic: Bool
    public let showsDecoration: Bool

    public init(context: SlicingContext) {
        self.init(traits: context.traits)
    }

    public init(traits: BTraits) {
        let uiTraits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: traits.mode == .dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: traits.accessibility
                .isDarkerSystemColorsEnabled ? .high : .normal),
        ])
        background = Color(uiColor: UIColor.systemBackground.resolvedColor(with: uiTraits))
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
        dimensionScales = [:]
        motionIsStatic = true
        showsDecoration = false
    }

    public var appearance: ViewDocumentAppearance {
        .init(background: background, dimensionScales: dimensionScales)
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
