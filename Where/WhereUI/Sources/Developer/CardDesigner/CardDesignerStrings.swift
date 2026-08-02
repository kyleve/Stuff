#if DEBUG
    import Foundation

    extension LocalizedStringResource {
        static let cardDesignerAppearance = LocalizedStringResource("Appearance")
        static let cardDesignerApplyFooter =
            LocalizedStringResource(
                "When enabled, changes appear on every location card until you turn this off or reset the studio.",
            )
        static let cardDesignerApplyToApp = LocalizedStringResource("Apply to App")
        static let cardDesignerArc = LocalizedStringResource("Curved Label")
        static let cardDesignerArcTypography = LocalizedStringResource("Curved Label Type")
        static let cardDesignerArtworkHeight = LocalizedStringResource("Artwork Height")
        static let cardDesignerArtworkWidth = LocalizedStringResource("Artwork Width")
        static let cardDesignerBlendMode = LocalizedStringResource("Blend Mode")
        static let cardDesignerCard = LocalizedStringResource("Card Geometry")
        static let cardDesignerCenterX = LocalizedStringResource("Horizontal Center")
        static let cardDesignerCenterY = LocalizedStringResource("Vertical Center")
        static let cardDesignerColor = LocalizedStringResource("Color")
        static let cardDesignerContentSpacing = LocalizedStringResource("Content Spacing")
        static let cardDesignerCopiedJSON = LocalizedStringResource("Copied JSON")
        static let cardDesignerCopiedSwift = LocalizedStringResource("Copied Swift")
        static let cardDesignerCopyJSON = LocalizedStringResource("Copy JSON")
        static let cardDesignerCopySwift = LocalizedStringResource("Copy Swift")
        static let cardDesignerCornerRadius = LocalizedStringResource("Corner Radius")
        static let cardDesignerDark = LocalizedStringResource("Dark")
        static let cardDesignerDarkInk = LocalizedStringResource("Dark Appearance Ink")
        static let cardDesignerDashLength = LocalizedStringResource("Dash Length")
        static let cardDesignerDashSpacing = LocalizedStringResource("Dash Spacing")
        static let cardDesignerDayUnit = LocalizedStringResource("Day Unit")
        static let cardDesignerDesign = LocalizedStringResource("Design")
        static let cardDesignerDiffOnly = LocalizedStringResource("Diff Only")
        static let cardDesignerEntryStamp = LocalizedStringResource("Entry Stamp")
        static let cardDesignerExport = LocalizedStringResource("Export")
        static let cardDesignerExportFooter =
            LocalizedStringResource(
                "Share or copy JSON and Swift output. Diff Only includes just values that differ from the app defaults.",
            )
        static let cardDesignerExtentHeight = LocalizedStringResource("Extent Height")
        static let cardDesignerExtentWidth = LocalizedStringResource("Extent Width")
        static let cardDesignerFallbackWatermarkSize =
            LocalizedStringResource("Fallback Watermark Size")
        static let cardDesignerFillOpacity = LocalizedStringResource("Fill Opacity")
        static let cardDesignerGlassAndInk = LocalizedStringResource("Glass and Security Ink")
        static let cardDesignerGlassTintOpacity = LocalizedStringResource("Glass Tint Opacity")
        static let cardDesignerGlow = LocalizedStringResource("Glow")
        static let cardDesignerGlyphSize = LocalizedStringResource("Glyph Size")
        static let cardDesignerHeroNumber = LocalizedStringResource("Day Count")
        static let cardDesignerInnerRing = LocalizedStringResource("Inner Ring")
        static let cardDesignerInset = LocalizedStringResource("Inset")
        static let cardDesignerInsetFraction = LocalizedStringResource("Inset Fraction")
        static let cardDesignerIntensity = LocalizedStringResource("Intensity")
        static let cardDesignerJSONExport = LocalizedStringResource("Card Design.json")
        static let cardDesignerLift = LocalizedStringResource("Lift Shadow")
        static let cardDesignerLight = LocalizedStringResource("Light")
        static let cardDesignerLightInk = LocalizedStringResource("Light Appearance Ink")
        static let cardDesignerLineWidth = LocalizedStringResource("Line Width")
        static let cardDesignerLineWidthFraction = LocalizedStringResource("Line Width Fraction")
        static let cardDesignerMaximumSweep = LocalizedStringResource("Maximum Sweep")
        static let cardDesignerMicroprint = LocalizedStringResource("Microprint Border")
        static let cardDesignerNameOpacity = LocalizedStringResource("Name Opacity")
        static let cardDesignerOffsetY = LocalizedStringResource("Vertical Offset")
        static let cardDesignerOpacity = LocalizedStringResource("Opacity")
        static let cardDesignerOuterRing = LocalizedStringResource("Outer Ring")
        static let cardDesignerPadding = LocalizedStringResource("Padding")
        static let cardDesignerPersistenceErrorTitle =
            LocalizedStringResource("Couldn't Save Card Design")
        static let cardDesignerPointSize = LocalizedStringResource("Point Size")
        static let cardDesignerPreview = LocalizedStringResource("Preview")
        static let cardDesignerPreviewCaption = LocalizedStringResource("Your days in this region")
        static let cardDesignerPrimaryRingSpacing = LocalizedStringResource("Primary Ring Spacing")
        static let cardDesignerPrimaryRosetteOpacity =
            LocalizedStringResource("Primary Rosette Opacity")
        static let cardDesignerProgressHeight = LocalizedStringResource("Progress Height")
        static let cardDesignerRadius = LocalizedStringResource("Radius")
        static let cardDesignerRadiusFraction = LocalizedStringResource("Radius Fraction")
        static let cardDesignerRegion = LocalizedStringResource("Region")
        static let cardDesignerRegionArtwork = LocalizedStringResource("Region Artwork")
        static let cardDesignerRegionName = LocalizedStringResource("Region Name")
        static let cardDesignerReset = LocalizedStringResource("Reset")
        static let cardDesignerResetAll = LocalizedStringResource("Reset Everything")
        static let cardDesignerResetAllMessage =
            LocalizedStringResource(
                "This restores every regular, compact, and shared card setting to the app defaults.",
            )
        static let cardDesignerResetAllTitle = LocalizedStringResource("Reset Card Designer?")
        static let cardDesignerResetShared = LocalizedStringResource("Reset Shared Settings")
        static let cardDesignerResetVariant = LocalizedStringResource("Reset This Variant")
        static let cardDesignerRosettes = LocalizedStringResource("Rosettes")
        static let cardDesignerRotation = LocalizedStringResource("Rotation")
        static let cardDesignerScale = LocalizedStringResource("Scale")
        static let cardDesignerSecondaryRingSpacing =
            LocalizedStringResource("Secondary Ring Spacing")
        static let cardDesignerSecondaryRosetteOpacity =
            LocalizedStringResource("Secondary Rosette Opacity")
        static let cardDesignerShareJSON = LocalizedStringResource("Share JSON")
        static let cardDesignerShareSwift = LocalizedStringResource("Share Swift")
        static let cardDesignerShadows = LocalizedStringResource("Shadows")
        static let cardDesignerSheen = LocalizedStringResource("Motion Sheen")
        static let cardDesignerShowArc = LocalizedStringResource("Show Curved Label")
        static let cardDesignerShowStroke = LocalizedStringResource("Show Stroke")
        static let cardDesignerSizeFraction = LocalizedStringResource("Size Fraction")
        static let cardDesignerSizeMode = LocalizedStringResource("Size Mode")
        static let cardDesignerSpacing = LocalizedStringResource("Spacing")
        static let cardDesignerSpacingFraction = LocalizedStringResource("Spacing Fraction")
        static let cardDesignerStampArtwork = LocalizedStringResource("Stamp Artwork")
        static let cardDesignerStampContent = LocalizedStringResource("Stamp Content")
        static let cardDesignerStampSize = LocalizedStringResource("Stamp Size")
        static let cardDesignerStaticGlint = LocalizedStringResource("Fallback Glint")
        static let cardDesignerStaticPitch = LocalizedStringResource("Fallback Pitch")
        static let cardDesignerStaticRoll = LocalizedStringResource("Fallback Roll")
        static let cardDesignerStrokeOpacity = LocalizedStringResource("Stroke Opacity")
        static let cardDesignerStrokeWidth = LocalizedStringResource("Stroke Width")
        static let cardDesignerSweepPerCharacter = LocalizedStringResource("Sweep Per Character")
        static let cardDesignerSwiftExport = LocalizedStringResource("Card Design.swift")
        static let cardDesignerSymbolTypography = LocalizedStringResource("Symbol Type")
        static let cardDesignerTextStyle = LocalizedStringResource("Text Style")
        static let cardDesignerTitle = LocalizedStringResource("Card Designer Studio")
        static let cardDesignerTracking = LocalizedStringResource("Tracking")
        static let cardDesignerTypography = LocalizedStringResource("Typography")
        static let cardDesignerUseRegionOutline = LocalizedStringResource("Use Region Outline")
        static let cardDesignerVariant = LocalizedStringResource("Variant")
        static let cardDesignerWatermark = LocalizedStringResource("Watermark")
        static let cardDesignerWatermarkOffsetX =
            LocalizedStringResource("Watermark Horizontal Offset")
        static let cardDesignerWatermarkOffsetY =
            LocalizedStringResource("Watermark Vertical Offset")
        static let cardDesignerWatermarkOpacity = LocalizedStringResource("Watermark Opacity")
        static let cardDesignerWeight = LocalizedStringResource("Weight")
        static let cardDesignerWhiteMix = LocalizedStringResource("White Mix")
        static let cardDesignerWobble = LocalizedStringResource("Wobble")
        static let cardDesignerYearTypography = LocalizedStringResource("Year Type")

        static func cardDesignerDays(_ value: Int) -> LocalizedStringResource {
            LocalizedStringResource("Days: \(value)")
        }

        static func cardDesignerYear(_ value: Int) -> LocalizedStringResource {
            LocalizedStringResource("Year: \(value)")
        }
    }

    extension CardDesignerConfiguration.Variant {
        var localizedName: String {
            switch self {
                case .regular: String(localized: "Regular")
                case .compact: String(localized: "Compact")
            }
        }
    }

    extension CardDesignerConfiguration.SizeMode {
        var localizedName: String {
            switch self {
                case .fixed: String(localized: "Fixed")
                case .semantic: String(localized: "Dynamic Type")
            }
        }
    }

    extension CardDesignerConfiguration.TextStyle {
        var localizedName: String {
            switch self {
                case .caption2: String(localized: "Caption 2")
                case .caption: String(localized: "Caption")
                case .footnote: String(localized: "Footnote")
                case .subheadline: String(localized: "Subheadline")
                case .callout: String(localized: "Callout")
                case .body: String(localized: "Body")
                case .headline: String(localized: "Headline")
                case .title3: String(localized: "Title 3")
                case .title2: String(localized: "Title 2")
                case .title: String(localized: "Title")
                case .largeTitle: String(localized: "Large Title")
            }
        }
    }

    extension CardDesignerConfiguration.FontWeight {
        var localizedName: String {
            switch self {
                case .ultraLight: String(localized: "Ultra Light")
                case .thin: String(localized: "Thin")
                case .light: String(localized: "Light")
                case .regular: String(localized: "Regular")
                case .medium: String(localized: "Medium")
                case .semibold: String(localized: "Semibold")
                case .bold: String(localized: "Bold")
                case .heavy: String(localized: "Heavy")
                case .black: String(localized: "Black")
            }
        }
    }

    extension CardDesignerConfiguration.FontDesign {
        var localizedName: String {
            switch self {
                case .default: String(localized: "Default")
                case .serif: String(localized: "Serif")
                case .rounded: String(localized: "Rounded")
                case .monospaced: String(localized: "Monospaced")
            }
        }
    }

    extension CardDesignerBlendMode {
        var localizedName: String {
            switch self {
                case .normal: String(localized: "Normal")
                case .multiply: String(localized: "Multiply")
                case .screen: String(localized: "Screen")
                case .overlay: String(localized: "Overlay")
                case .darken: String(localized: "Darken")
                case .lighten: String(localized: "Lighten")
                case .colorDodge: String(localized: "Color Dodge")
                case .colorBurn: String(localized: "Color Burn")
                case .softLight: String(localized: "Soft Light")
                case .hardLight: String(localized: "Hard Light")
                case .difference: String(localized: "Difference")
                case .exclusion: String(localized: "Exclusion")
                case .hue: String(localized: "Hue")
                case .saturation: String(localized: "Saturation")
                case .color: String(localized: "Color")
                case .luminosity: String(localized: "Luminosity")
                case .sourceAtop: String(localized: "Source Atop")
                case .destinationOver: String(localized: "Destination Over")
                case .destinationOut: String(localized: "Destination Out")
                case .plusDarker: String(localized: "Plus Darker")
                case .plusLighter: String(localized: "Plus Lighter")
            }
        }
    }
#endif
