import SwiftUI
import ViewDocumentCore

/// Host-resolved appearance inputs. Resolution does not consult ambient UIKit traits.
public struct ViewDocumentAppearance {
    public var background: Color
    public var dimensionScales: [ViewFontDescriptor.TextStyle: Double]

    public init(background: Color, dimensionScales: [ViewFontDescriptor.TextStyle: Double]) {
        self.background = background
        self.dimensionScales = dimensionScales
    }

    public func color(_ value: ViewColorDescriptor) -> Color {
        switch value {
            case let .rgba(red, green, blue, alpha): Color(
                    .sRGB,
                    red: red,
                    green: green,
                    blue: blue,
                    opacity: alpha,
                )
            case let .semantic(role):
                switch role {
                    case .primary: .primary
                    case .secondary: .secondary
                    case .accent: .accentColor
                    case .background: background
                }
        }
    }

    public func paint(_ value: ViewPaint) -> AnyShapeStyle {
        switch value {
            case let .color(value): AnyShapeStyle(color(value))
            case let .linearGradient(stops, start, end):
                AnyShapeStyle(LinearGradient(
                    stops: stops.map { .init(color: color($0.color), location: $0.location) },
                    startPoint: UnitPoint(x: start.x, y: start.y),
                    endPoint: UnitPoint(x: end.x, y: end.y),
                ))
        }
    }

    public func dimension(_ value: ViewDimension) -> CGFloat {
        switch value {
            case let .points(points): points
            case let .scaled(points, style): points * (dimensionScales[style] ?? 1)
        }
    }
}

extension ViewFontDescriptor {
    public var font: Font {
        let base: Font = switch size {
            case let .semantic(style): .system(style.textStyle, design: design?.fontDesign)
            case let .fixed(points):
                if let design { .system(size: points, design: design.fontDesign) }
                else { .system(size: points) }
        }
        return weight.map { base.weight($0.fontWeight) } ?? base
    }
}

extension ViewFontDescriptor.TextStyle {
    public var textStyle: Font.TextStyle {
        switch self {
            case .largeTitle: .largeTitle
            case .title: .title
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption
            case .caption2: .caption2
        }
    }
}

extension ViewFontDescriptor.Weight {
    public var fontWeight: Font.Weight {
        switch self {
            case .ultraLight: .ultraLight
            case .thin: .thin
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
        }
    }
}

extension ViewFontDescriptor.Design {
    public var fontDesign: Font.Design {
        switch self {
            case .standard: .default
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
        }
    }
}

extension ViewAlignment {
    public var alignment: Alignment {
        switch self {
            case .topLeading: .topLeading
            case .top: .top
            case .topTrailing: .topTrailing
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
            case .bottomLeading: .bottomLeading
            case .bottom: .bottom
            case .bottomTrailing: .bottomTrailing
        }
    }
}

extension ViewModifierDescriptor.Blend {
    public var blendMode: BlendMode {
        switch self {
            case .normal: .normal
            case .multiply: .multiply
            case .screen: .screen
            case .overlay: .overlay
            case .darken: .darken
            case .lighten: .lighten
            case .plusLighter: .plusLighter
        }
    }
}
