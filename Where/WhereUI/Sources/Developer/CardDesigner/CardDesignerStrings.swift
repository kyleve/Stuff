#if DEBUG
    import Foundation

    extension CardDesignerConfiguration.Variant {
        var localizedName: String {
            switch self {
                case .regular: String(localized: .cardDesignerVariantRegular)
                case .compact: String(localized: .cardDesignerVariantCompact)
            }
        }
    }

    extension CardDesignerConfiguration.SizeMode {
        var localizedName: String {
            switch self {
                case .fixed: String(localized: .cardDesignerSizeModeFixed)
                case .semantic: String(localized: .cardDesignerSizeModeSemantic)
            }
        }
    }

    extension CardDesignerConfiguration.TextStyle {
        var localizedName: String {
            switch self {
                case .caption2: String(localized: .cardDesignerTextStyleCaption2)
                case .caption: String(localized: .cardDesignerTextStyleCaption)
                case .footnote: String(localized: .cardDesignerTextStyleFootnote)
                case .subheadline: String(localized: .cardDesignerTextStyleSubheadline)
                case .callout: String(localized: .cardDesignerTextStyleCallout)
                case .body: String(localized: .cardDesignerTextStyleBody)
                case .headline: String(localized: .cardDesignerTextStyleHeadline)
                case .title3: String(localized: .cardDesignerTextStyleTitle3)
                case .title2: String(localized: .cardDesignerTextStyleTitle2)
                case .title: String(localized: .cardDesignerTextStyleTitle)
                case .largeTitle: String(localized: .cardDesignerTextStyleLargeTitle)
            }
        }
    }

    extension CardDesignerConfiguration.FontWeight {
        var localizedName: String {
            switch self {
                case .ultraLight: String(localized: .cardDesignerFontWeightUltraLight)
                case .thin: String(localized: .cardDesignerFontWeightThin)
                case .light: String(localized: .cardDesignerFontWeightLight)
                case .regular: String(localized: .cardDesignerFontWeightRegular)
                case .medium: String(localized: .cardDesignerFontWeightMedium)
                case .semibold: String(localized: .cardDesignerFontWeightSemibold)
                case .bold: String(localized: .cardDesignerFontWeightBold)
                case .heavy: String(localized: .cardDesignerFontWeightHeavy)
                case .black: String(localized: .cardDesignerFontWeightBlack)
            }
        }
    }

    extension CardDesignerConfiguration.FontDesign {
        var localizedName: String {
            switch self {
                case .default: String(localized: .cardDesignerFontDesignDefault)
                case .serif: String(localized: .cardDesignerFontDesignSerif)
                case .rounded: String(localized: .cardDesignerFontDesignRounded)
                case .monospaced: String(localized: .cardDesignerFontDesignMonospaced)
            }
        }
    }

    extension CardDesignerBlendMode {
        var localizedName: String {
            switch self {
                case .normal: String(localized: .cardDesignerBlendNormal)
                case .multiply: String(localized: .cardDesignerBlendMultiply)
                case .screen: String(localized: .cardDesignerBlendScreen)
                case .overlay: String(localized: .cardDesignerBlendOverlay)
                case .darken: String(localized: .cardDesignerBlendDarken)
                case .lighten: String(localized: .cardDesignerBlendLighten)
                case .colorDodge: String(localized: .cardDesignerBlendColorDodge)
                case .colorBurn: String(localized: .cardDesignerBlendColorBurn)
                case .softLight: String(localized: .cardDesignerBlendSoftLight)
                case .hardLight: String(localized: .cardDesignerBlendHardLight)
                case .difference: String(localized: .cardDesignerBlendDifference)
                case .exclusion: String(localized: .cardDesignerBlendExclusion)
                case .hue: String(localized: .cardDesignerBlendHue)
                case .saturation: String(localized: .cardDesignerBlendSaturation)
                case .color: String(localized: .cardDesignerBlendColor)
                case .luminosity: String(localized: .cardDesignerBlendLuminosity)
                case .sourceAtop: String(localized: .cardDesignerBlendSourceAtop)
                case .destinationOver: String(localized: .cardDesignerBlendDestinationOver)
                case .destinationOut: String(localized: .cardDesignerBlendDestinationOut)
                case .plusDarker: String(localized: .cardDesignerBlendPlusDarker)
                case .plusLighter: String(localized: .cardDesignerBlendPlusLighter)
            }
        }
    }
#endif
