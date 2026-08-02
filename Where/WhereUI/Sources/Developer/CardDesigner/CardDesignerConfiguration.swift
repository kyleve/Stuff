#if DEBUG
    import Foundation
    import SwiftUI

    /// Versioned, Codable card appearance edited by the DEBUG card designer.
    /// It contains presentation only: count animation and RegionKit cache policy
    /// remain owned by the production stylesheet and path cache.
    struct CardDesignerConfiguration: Codable, Equatable {
        static let currentSchemaVersion = 1
        static let standard = CardDesignerConfiguration(styles: .standard)

        var schemaVersion = currentSchemaVersion
        var regular: Card
        var compact: Card
        var shared: Shared

        enum Variant: String, CaseIterable, Codable {
            case regular
            case compact

            var style: WhereStylesheet.CardStyle.Variant {
                switch self {
                    case .regular: .regular
                    case .compact: .compact
                }
            }
        }

        subscript(_ variant: Variant) -> Card {
            get {
                switch variant {
                    case .regular: regular
                    case .compact: compact
                }
            }
            set {
                switch variant {
                    case .regular: regular = newValue
                    case .compact: compact = newValue
                }
            }
        }

        init(styles: WhereStylesheet.CardStyles) {
            guard
                let fallbackRegionShape = styles.regular.regionShape,
                let fallbackArc = styles.regular.entryStamp.arc
            else {
                preconditionFailure("The regular card must provide designer fallback artwork.")
            }
            regular = Card(
                styles.regular,
                fallbackRegionShape: fallbackRegionShape,
                fallbackArc: fallbackArc,
            )
            compact = Card(
                styles.compact,
                fallbackRegionShape: fallbackRegionShape,
                fallbackArc: fallbackArc,
            )
            shared = Shared(styles)
        }

        func resolve(
            over base: WhereStylesheet.CardStyles,
            colorScheme: ColorScheme,
        ) -> WhereStylesheet.CardStyles {
            var resolved = base
            resolved.regular = regular.style
            resolved.compact = compact.style
            resolved.watermarkOpacity = shared.watermarkOpacity
            resolved.glassTintOpacity = shared.glassTintOpacity
            resolved.nameOpacity = shared.nameOpacity
            resolved.rosetteFill = .init(
                primary: shared.primaryRosetteOpacity,
                secondary: shared.secondaryRosetteOpacity,
            )
            resolved.securityPrint = shared.securityPrint(for: colorScheme).style
            return resolved
        }

        struct Card: Codable, Equatable {
            var cornerRadius: CGFloat
            var padding: CGFloat
            var contentSpacing: CGFloat
            var progressBarHeight: CGFloat
            var entryStamp: EntryStamp
            var regionNameTypography: Typography
            var regionNameTracking: CGFloat
            var heroNumberTypography: Typography
            var dayUnitTypography: Typography
            var watermarkFontSize: CGFloat
            var watermarkOffset: Offset
            var usesRegionShape: Bool
            var regionShape: RegionShape
            var sheen: Sheen
            var rosette: Rosette
            var glow: Shadow
            var lift: Shadow

            init(
                _ style: WhereStylesheet.CardStyle,
                fallbackRegionShape: WhereStylesheet.CardStyle.RegionShape,
                fallbackArc: WhereStylesheet.CardStyle.EntryStamp.Arc,
            ) {
                cornerRadius = style.cornerRadius
                padding = style.padding
                contentSpacing = style.contentSpacing
                progressBarHeight = style.progressBarHeight
                entryStamp = EntryStamp(style.entryStamp, fallbackArc: fallbackArc)
                regionNameTypography = Typography(style.regionNameTypography)
                regionNameTracking = style.regionNameTracking
                heroNumberTypography = Typography(style.heroNumberTypography)
                dayUnitTypography = Typography(style.dayUnitTypography)
                watermarkFontSize = style.watermarkFontSize
                watermarkOffset = Offset(style.watermarkOffset)
                usesRegionShape = style.regionShape != nil
                regionShape = RegionShape(style.regionShape ?? fallbackRegionShape)
                sheen = Sheen(style.sheen)
                rosette = Rosette(style.rosette)
                glow = Shadow(style.glow)
                lift = Shadow(style.lift)
            }

            var style: WhereStylesheet.CardStyle {
                .init(
                    cornerRadius: cornerRadius,
                    padding: padding,
                    contentSpacing: contentSpacing,
                    progressBarHeight: progressBarHeight,
                    entryStamp: entryStamp.style,
                    regionNameTypography: regionNameTypography.style,
                    regionNameTracking: regionNameTracking,
                    heroNumberTypography: heroNumberTypography.style,
                    dayUnitTypography: dayUnitTypography.style,
                    watermarkFontSize: watermarkFontSize,
                    watermarkOffset: watermarkOffset.size,
                    regionShape: usesRegionShape ? regionShape.style : nil,
                    sheen: sheen.style,
                    rosette: rosette.style,
                    glow: glow.style,
                    lift: lift.style,
                )
            }
        }

        struct Shared: Codable, Equatable {
            var watermarkOpacity: Double
            var glassTintOpacity: Double
            var nameOpacity: Double
            var primaryRosetteOpacity: Double
            var secondaryRosetteOpacity: Double
            var lightSecurityPrint: SecurityPrint
            var darkSecurityPrint: SecurityPrint

            init(_ styles: WhereStylesheet.CardStyles) {
                watermarkOpacity = styles.watermarkOpacity
                glassTintOpacity = styles.glassTintOpacity
                nameOpacity = styles.nameOpacity
                primaryRosetteOpacity = styles.rosetteFill.primary
                secondaryRosetteOpacity = styles.rosetteFill.secondary
                lightSecurityPrint = SecurityPrint(.standard)
                darkSecurityPrint = SecurityPrint(.dark)
            }

            func securityPrint(for colorScheme: ColorScheme) -> SecurityPrint {
                switch colorScheme {
                    case .light: lightSecurityPrint
                    case .dark: darkSecurityPrint
                    @unknown default: lightSecurityPrint
                }
            }
        }

        struct Typography: Codable, Equatable {
            var sizeMode: SizeMode
            var fixedSize: CGFloat
            var textStyle: TextStyle
            var weight: FontWeight
            var design: FontDesign

            init(_ typography: WhereStylesheet.CardStyle.Typography) {
                switch typography.size {
                    case let .fixed(points):
                        sizeMode = .fixed
                        fixedSize = points
                        textStyle = .body
                    case let .semantic(textStyle):
                        sizeMode = .semantic
                        fixedSize = 17
                        self.textStyle = TextStyle(textStyle)
                }
                weight = FontWeight(typography.weight)
                design = FontDesign(typography.design)
            }

            var style: WhereStylesheet.CardStyle.Typography {
                .init(
                    size: size,
                    weight: weight.style,
                    design: design.style,
                )
            }

            private var size: WhereStylesheet.CardStyle.Typography.Size {
                switch sizeMode {
                    case .fixed: .fixed(fixedSize)
                    case .semantic: .semantic(textStyle.style)
                }
            }
        }

        enum SizeMode: String, CaseIterable, Codable {
            case fixed
            case semantic
        }

        enum TextStyle: String, CaseIterable, Codable {
            case caption2
            case caption
            case footnote
            case subheadline
            case callout
            case body
            case headline
            case title3
            case title2
            case title
            case largeTitle

            init(_ style: WhereStylesheet.CardStyle.Typography.TextStyle) {
                self = TextStyle(rawValue: style.rawValue) ?? .body
            }

            var style: WhereStylesheet.CardStyle.Typography.TextStyle {
                .init(rawValue: rawValue) ?? .body
            }
        }

        enum FontWeight: String, CaseIterable, Codable {
            case ultraLight
            case thin
            case light
            case regular
            case medium
            case semibold
            case bold
            case heavy
            case black

            init(_ weight: WhereStylesheet.CardStyle.Typography.Weight) {
                self = FontWeight(rawValue: weight.rawValue) ?? .regular
            }

            var style: WhereStylesheet.CardStyle.Typography.Weight {
                .init(rawValue: rawValue) ?? .regular
            }

            var fontWeight: Font.Weight {
                style.fontWeight
            }
        }

        enum FontDesign: String, CaseIterable, Codable {
            case `default`
            case serif
            case rounded
            case monospaced

            init(_ design: WhereStylesheet.CardStyle.Typography.Design) {
                self = FontDesign(rawValue: design.rawValue) ?? .default
            }

            var style: WhereStylesheet.CardStyle.Typography.Design {
                .init(rawValue: rawValue) ?? .default
            }

            var fontDesign: Font.Design {
                style.fontDesign
            }
        }

        struct EntryStamp: Codable, Equatable {
            var size: CGFloat
            var outerRing: Ring
            var innerRing: DashedRing
            var content: StampContent
            var showsArc: Bool
            var arc: Arc
            var rotationDegrees: Double

            init(
                _ style: WhereStylesheet.CardStyle.EntryStamp,
                fallbackArc: WhereStylesheet.CardStyle.EntryStamp.Arc,
            ) {
                size = style.size
                outerRing = Ring(style.outerRing)
                innerRing = DashedRing(style.innerRing)
                content = StampContent(style.content)
                showsArc = style.arc != nil
                arc = Arc(style.arc ?? fallbackArc)
                rotationDegrees = style.rotationDegrees
            }

            var style: WhereStylesheet.CardStyle.EntryStamp {
                .init(
                    size: size,
                    outerRing: outerRing.style,
                    innerRing: innerRing.style,
                    content: content.style,
                    arc: showsArc ? arc.style : nil,
                    rotationDegrees: rotationDegrees,
                )
            }
        }

        struct Ring: Codable, Equatable {
            var opacity: Double
            var lineWidthFraction: CGFloat

            init(_ style: WhereStylesheet.CardStyle.EntryStamp.Ring) {
                opacity = style.opacity
                lineWidthFraction = style.lineWidthFraction
            }

            var style: WhereStylesheet.CardStyle.EntryStamp.Ring {
                .init(opacity: opacity, lineWidthFraction: lineWidthFraction)
            }
        }

        struct DashedRing: Codable, Equatable {
            var opacity: Double
            var lineWidthFraction: CGFloat
            var dashLengthFraction: CGFloat
            var dashSpacingFraction: CGFloat
            var insetFraction: CGFloat

            init(_ style: WhereStylesheet.CardStyle.EntryStamp.DashedRing) {
                opacity = style.opacity
                lineWidthFraction = style.lineWidthFraction
                dashLengthFraction = style.dash.lengthFraction
                dashSpacingFraction = style.dash.spacingFraction
                insetFraction = style.insetFraction
            }

            var style: WhereStylesheet.CardStyle.EntryStamp.DashedRing {
                .init(
                    opacity: opacity,
                    lineWidthFraction: lineWidthFraction,
                    dash: .init(
                        lengthFraction: dashLengthFraction,
                        spacingFraction: dashSpacingFraction,
                    ),
                    insetFraction: insetFraction,
                )
            }
        }

        struct StampContent: Codable, Equatable {
            var spacingFraction: CGFloat
            var artworkExtent: Dimensions
            var symbolFont: FractionalTypography
            var yearFont: FractionalTypography
            var opacity: Double

            init(_ style: WhereStylesheet.CardStyle.EntryStamp.Content) {
                spacingFraction = style.spacingFraction
                artworkExtent = Dimensions(style.artworkExtent)
                symbolFont = FractionalTypography(style.symbolFont)
                yearFont = FractionalTypography(style.yearFont)
                opacity = style.opacity
            }

            var style: WhereStylesheet.CardStyle.EntryStamp.Content {
                .init(
                    spacingFraction: spacingFraction,
                    artworkExtent: artworkExtent.size,
                    symbolFont: symbolFont.style,
                    yearFont: yearFont.style,
                    opacity: opacity,
                )
            }
        }

        struct Arc: Codable, Equatable {
            var radiusFraction: CGFloat
            var font: FractionalTypography
            var opacity: Double
            var maximumSweepDegrees: Double
            var sweepDegreesPerCharacter: Double

            init(_ style: WhereStylesheet.CardStyle.EntryStamp.Arc) {
                radiusFraction = style.radiusFraction
                font = FractionalTypography(style.font)
                opacity = style.opacity
                maximumSweepDegrees = style.maximumSweepDegrees
                sweepDegreesPerCharacter = style.sweepDegreesPerCharacter
            }

            var style: WhereStylesheet.CardStyle.EntryStamp.Arc {
                .init(
                    radiusFraction: radiusFraction,
                    font: font.style,
                    opacity: opacity,
                    maximumSweepDegrees: maximumSweepDegrees,
                    sweepDegreesPerCharacter: sweepDegreesPerCharacter,
                )
            }
        }

        struct FractionalTypography: Codable, Equatable {
            var sizeFraction: CGFloat
            var weight: FontWeight
            var design: FontDesign

            init(_ style: WhereStylesheet.CardStyle.EntryStamp.Typography) {
                sizeFraction = style.sizeFraction
                weight = FontWeight(style.weight)
                design = FontDesign(style.design)
            }

            var style: WhereStylesheet.CardStyle.EntryStamp.Typography {
                .init(
                    sizeFraction: sizeFraction,
                    weight: weight.fontWeight,
                    design: design.fontDesign,
                )
            }
        }

        struct RegionShape: Codable, Equatable {
            var watermark: Artwork
            var stamp: Artwork
            var securityBorder: SecurityBorder

            init(_ style: WhereStylesheet.CardStyle.RegionShape) {
                let fallbackStroke = style.watermark.stroke
                    ?? .init(opacity: 0.25, width: 1)
                watermark = Artwork(style.watermark, fallbackStroke: fallbackStroke)
                stamp = Artwork(style.stamp, fallbackStroke: fallbackStroke)
                securityBorder = SecurityBorder(style.securityBorder)
            }

            var style: WhereStylesheet.CardStyle.RegionShape {
                .init(
                    watermark: watermark.style,
                    stamp: stamp.style,
                    securityBorder: securityBorder.style,
                )
            }
        }

        struct Artwork: Codable, Equatable {
            var center: Point
            var extent: Dimensions
            var scale: CGFloat
            var fillOpacity: Double
            var showsStroke: Bool
            var stroke: Stroke

            init(
                _ style: WhereStylesheet.CardStyle.RegionShape.Artwork,
                fallbackStroke: WhereStylesheet.CardStyle.RegionShape.Artwork.Stroke,
            ) {
                center = Point(style.center)
                extent = Dimensions(style.extent)
                scale = style.scale
                fillOpacity = style.fillOpacity
                showsStroke = style.stroke != nil
                stroke = Stroke(style.stroke ?? fallbackStroke)
            }

            var style: WhereStylesheet.CardStyle.RegionShape.Artwork {
                .init(
                    center: center.point,
                    extent: extent.size,
                    scale: scale,
                    fillOpacity: fillOpacity,
                    stroke: showsStroke ? stroke.style : nil,
                )
            }
        }

        struct Stroke: Codable, Equatable {
            var opacity: Double
            var width: CGFloat

            init(_ style: WhereStylesheet.CardStyle.RegionShape.Artwork.Stroke) {
                opacity = style.opacity
                width = style.width
            }

            var style: WhereStylesheet.CardStyle.RegionShape.Artwork.Stroke {
                .init(opacity: opacity, width: width)
            }
        }

        struct SecurityBorder: Codable, Equatable {
            var inset: CGFloat
            var glyphSize: CGFloat
            var spacing: CGFloat
            var opacity: Double

            init(_ style: WhereStylesheet.CardStyle.RegionShape.SecurityBorder) {
                inset = style.inset
                glyphSize = style.glyphSize
                spacing = style.spacing
                opacity = style.opacity
            }

            var style: WhereStylesheet.CardStyle.RegionShape.SecurityBorder {
                .init(inset: inset, glyphSize: glyphSize, spacing: spacing, opacity: opacity)
            }
        }

        struct Sheen: Codable, Equatable {
            var intensity: Double
            var staticGlintIntensity: Double
            var staticRoll: Double
            var staticPitch: Double

            init(_ style: WhereStylesheet.CardStyle.Sheen) {
                intensity = style.intensity
                staticGlintIntensity = style.staticGlintIntensity
                staticRoll = style.staticPose.roll
                staticPitch = style.staticPose.pitch
            }

            var style: WhereStylesheet.CardStyle.Sheen {
                .init(
                    intensity: intensity,
                    staticGlintIntensity: staticGlintIntensity,
                    staticPose: .init(roll: staticRoll, pitch: staticPitch),
                )
            }
        }

        struct Rosette: Codable, Equatable {
            var wobble: CGFloat
            var lineWidth: CGFloat
            var primaryRingSpacing: CGFloat
            var secondaryRingSpacing: CGFloat

            init(_ style: WhereStylesheet.CardStyle.Rosette) {
                wobble = style.wobble
                lineWidth = style.lineWidth
                primaryRingSpacing = style.primaryRingSpacing
                secondaryRingSpacing = style.secondaryRingSpacing
            }

            var style: WhereStylesheet.CardStyle.Rosette {
                .init(
                    wobble: wobble,
                    lineWidth: lineWidth,
                    primaryRingSpacing: primaryRingSpacing,
                    secondaryRingSpacing: secondaryRingSpacing,
                )
            }
        }

        struct Shadow: Codable, Equatable {
            var opacity: Double
            var radius: CGFloat
            var offsetY: CGFloat

            init(_ style: WhereStylesheet.CardStyle.Shadow) {
                opacity = style.opacity
                radius = style.radius
                offsetY = style.offsetY
            }

            var style: WhereStylesheet.CardStyle.Shadow {
                .init(opacity: opacity, radius: radius, offsetY: offsetY)
            }
        }

        struct SecurityPrint: Codable, Equatable {
            var whiteMix: Double
            var blendMode: CardDesignerBlendMode

            init(_ style: WhereStylesheet.CardStyles.SecurityPrint) {
                whiteMix = style.whiteMix
                blendMode = CardDesignerBlendMode(style.backgroundBlendMode)
            }

            var style: WhereStylesheet.CardStyles.SecurityPrint {
                .init(whiteMix: whiteMix, backgroundBlendMode: blendMode.style)
            }
        }

        struct Point: Codable, Equatable {
            var x: CGFloat
            var y: CGFloat

            init(_ point: CGPoint) {
                x = point.x
                y = point.y
            }

            var point: CGPoint {
                CGPoint(x: x, y: y)
            }
        }

        struct Dimensions: Codable, Equatable {
            var width: CGFloat
            var height: CGFloat

            init(_ size: CGSize) {
                width = size.width
                height = size.height
            }

            var size: CGSize {
                CGSize(width: width, height: height)
            }
        }

        struct Offset: Codable, Equatable {
            var x: CGFloat
            var y: CGFloat

            init(_ size: CGSize) {
                x = size.width
                y = size.height
            }

            var size: CGSize {
                CGSize(width: x, height: y)
            }
        }
    }

    enum CardDesignerBlendMode: String, CaseIterable, Codable {
        case normal
        case multiply
        case screen
        case overlay
        case darken
        case lighten
        case colorDodge
        case colorBurn
        case softLight
        case hardLight
        case difference
        case exclusion
        case hue
        case saturation
        case color
        case luminosity
        case sourceAtop
        case destinationOver
        case destinationOut
        case plusDarker
        case plusLighter

        init(_ mode: BlendMode) {
            switch mode {
                case .normal: self = .normal
                case .multiply: self = .multiply
                case .screen: self = .screen
                case .overlay: self = .overlay
                case .darken: self = .darken
                case .lighten: self = .lighten
                case .colorDodge: self = .colorDodge
                case .colorBurn: self = .colorBurn
                case .softLight: self = .softLight
                case .hardLight: self = .hardLight
                case .difference: self = .difference
                case .exclusion: self = .exclusion
                case .hue: self = .hue
                case .saturation: self = .saturation
                case .color: self = .color
                case .luminosity: self = .luminosity
                case .sourceAtop: self = .sourceAtop
                case .destinationOver: self = .destinationOver
                case .destinationOut: self = .destinationOut
                case .plusDarker: self = .plusDarker
                case .plusLighter: self = .plusLighter
                @unknown default: self = .normal
            }
        }

        var style: BlendMode {
            switch self {
                case .normal: .normal
                case .multiply: .multiply
                case .screen: .screen
                case .overlay: .overlay
                case .darken: .darken
                case .lighten: .lighten
                case .colorDodge: .colorDodge
                case .colorBurn: .colorBurn
                case .softLight: .softLight
                case .hardLight: .hardLight
                case .difference: .difference
                case .exclusion: .exclusion
                case .hue: .hue
                case .saturation: .saturation
                case .color: .color
                case .luminosity: .luminosity
                case .sourceAtop: .sourceAtop
                case .destinationOver: .destinationOver
                case .destinationOut: .destinationOut
                case .plusDarker: .plusDarker
                case .plusLighter: .plusLighter
            }
        }
    }

    extension CardDesignerConfiguration.FontWeight {
        fileprivate init(_ weight: Font.Weight) {
            switch weight {
                case .ultraLight: self = .ultraLight
                case .thin: self = .thin
                case .light: self = .light
                case .regular: self = .regular
                case .medium: self = .medium
                case .semibold: self = .semibold
                case .bold: self = .bold
                case .heavy: self = .heavy
                case .black: self = .black
                default: self = .regular
            }
        }
    }

    extension CardDesignerConfiguration.FontDesign {
        fileprivate init(_ design: Font.Design) {
            switch design {
                case .default: self = .default
                case .serif: self = .serif
                case .rounded: self = .rounded
                case .monospaced: self = .monospaced
                default: self = .default
            }
        }
    }
#endif
